import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/transcriber/domain/engine/engine_failure.dart';
import '../../features/transcriber/domain/engine/engine_types.dart';
import '../../features/transcriber/domain/ports/audio_preparation.dart';
import '../../features/transcriber/domain/ports/cancellation_signal.dart';
import 'audio_process_runner.dart';
import 'ffmpeg_toolchain.dart';
import 'managed_audio_preparation.dart';
import 'wav_format.dart';

typedef TemporaryDirectoryProvider = Future<Directory> Function();

/// Native audio preparation behind the domain [AudioPreparation] port.
///
/// Only application-managed capture IDs are accepted; the adapter resolves
/// `<temp>/persian_transcriber/captures/<sourceId>/capture.wav`. FFmpeg runs in
/// a dedicated worker isolate and writes
/// `<temp>/persian_transcriber/jobs/<jobId>/prepared.wav`.
///
/// The adapter never opens a network protocol, never searches PATH and never
/// deletes captures, models, transcripts or exports. Cleanup is scoped to the
/// exact job directory and is idempotent.
final class FfmpegAudioPreparation implements ManagedAudioPreparation {
  FfmpegAudioPreparation({
    required FfmpegToolchainConfig toolchainConfig,
    TemporaryDirectoryProvider? temporaryDirectory,
  })  : _config = toolchainConfig,
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final FfmpegToolchainConfig _config;
  final TemporaryDirectoryProvider _temporaryDirectory;

  _PreparationWorkerClient? _worker;
  Future<_PreparationWorkerClient>? _workerFuture;
  String? _activeRequestId;
  String? _activeJobId;
  bool _preparing = false;
  int _requestSequence = 0;
  bool _disposed = false;
  Future<void>? _disposal;

  @override
  Future<List<PreparedAudio>> prepare({
    required String sourceId,
    required String jobId,
    required CancellationSignal cancellation,
  }) async {
    _ensureNotDisposed();
    cancellation.throwIfCancelled();
    final source = _requireId(sourceId, 'capture');
    final job = _requireId(jobId, 'job');
    if (_preparing) {
      throw const EngineFailure(
        EngineFailureCode.busy,
        'Audio preparation is already active.',
      );
    }
    _preparing = true;

    try {
      final sourceFile = await _captureFile(source);
      final sourceStat = await _statOrNull(sourceFile);
      if (sourceStat == null ||
          sourceStat.type != FileSystemEntityType.file ||
          sourceStat.size <= 0) {
        throw const EngineFailure(
          EngineFailureCode.invalidAudio,
          'The managed capture is missing or empty.',
        );
      }

      final jobDirectory = await _jobDirectory(job);
      try {
        if (await jobDirectory.exists()) {
          await jobDirectory.delete(recursive: true);
        }
        await jobDirectory.create(recursive: true);
      } on FileSystemException {
        throw const EngineFailure(
          EngineFailureCode.ioError,
          'Temporary audio preparation storage could not be created.',
        );
      }

      final outputFile = File(p.join(jobDirectory.path, 'prepared.wav'));
      final requestId = 'prepare-'
          '${DateTime.now().toUtc().microsecondsSinceEpoch}-'
          '${_requestSequence++}';
      _activeRequestId = requestId;
      _activeJobId = job;

      try {
        final client = await _ensureWorker();
        cancellation.throwIfCancelled();

        final outcomeFuture = client.request(
          requestId: requestId,
          sourcePath: sourceFile.path,
          outputPath: outputFile.path,
        );
        unawaited(
          cancellation.whenCancelled.then((_) => client.cancel(requestId)),
        );

        final outcome = await outcomeFuture;
        cancellation.throwIfCancelled();
        switch (outcome) {
          case _PreparationCompleted(:final duration):
            if (duration <= Duration.zero) {
              throw const FormatException(
                'Prepared audio has no positive duration.',
              );
            }
            final format = WavFormat.read(outputFile);
            return List<PreparedAudio>.unmodifiable([
              PreparedAudio(audioId: job, duration: format.duration),
            ]);
          case _PreparationFailed(:final code, :final message):
            throw EngineFailure(code, message);
        }
      } on EngineFailure {
        await _deleteJobDirectoryQuietly(job);
        rethrow;
      } on FormatException catch (error) {
        await _deleteJobDirectoryQuietly(job);
        throw EngineFailure(
          EngineFailureCode.invalidAudio,
          'Prepared audio failed validation: ${error.message}',
        );
      } on FileSystemException {
        await _deleteJobDirectoryQuietly(job);
        throw const EngineFailure(
          EngineFailureCode.ioError,
          'Prepared audio could not be read.',
        );
      } on ArgumentError {
        await _deleteJobDirectoryQuietly(job);
        throw const EngineFailure(
          EngineFailureCode.invalidAudio,
          'Prepared audio metadata is invalid.',
        );
      } finally {
        if (_activeRequestId == requestId) {
          _activeRequestId = null;
          _activeJobId = null;
        }
      }
    } finally {
      _preparing = false;
    }
  }

  @override
  Future<void> cleanup(String jobId) async {
    final job = _requireId(jobId, 'job');
    if (_preparing || _activeJobId == job) {
      throw const EngineFailure(
        EngineFailureCode.busy,
        'Cannot clean up while audio preparation is active.',
      );
    }
    await _deleteJobDirectory(job);
  }

  @override
  Future<void> sweepStaleJobs({
    Duration maxAge = const Duration(hours: 24),
    DateTime? now,
  }) async {
    if (maxAge <= Duration.zero) {
      throw ArgumentError.value(maxAge, 'maxAge', 'Must be positive');
    }
    final root = await _jobsRoot();
    if (!await root.exists()) return;

    final cutoff = (now ?? DateTime.now()).subtract(maxAge);
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      if (_activeJobId != null && p.basename(entity.path) == _activeJobId) {
        continue;
      }
      try {
        final lastActivity = await _jobLastActivity(entity);
        if (lastActivity.isBefore(cutoff)) {
          await entity.delete(recursive: true);
        }
      } on FileSystemException {
        // Best effort. A later sweep can retry a locked directory.
      }
    }
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;

    final worker = _worker;
    _worker = null;
    final pendingWorker = _workerFuture;
    _workerFuture = null;

    if (worker != null) {
      await worker.shutdown();
    }
    if (pendingWorker != null) {
      try {
        final lateWorker = await pendingWorker;
        await lateWorker.shutdown();
      } on Object {
        // Spawn already failed or timed out; there is no worker to close.
      }
    }
  }

  Future<_PreparationWorkerClient> _ensureWorker() async {
    final existing = _worker;
    if (existing != null && existing.isAlive) return existing;
    if (existing != null) {
      _worker = null;
      await existing.shutdown();
    }

    final pending = _workerFuture ??= _PreparationWorkerClient.spawn(_config);
    try {
      final client = await pending;
      if (!_disposed) _worker = client;
      return client;
    } on EngineFailure {
      rethrow;
    } on Object {
      throw const EngineFailure(
        EngineFailureCode.ioError,
        'The FFmpeg preparation worker could not start.',
      );
    } finally {
      if (identical(_workerFuture, pending)) _workerFuture = null;
    }
  }

  Future<File> _captureFile(String captureId) async {
    final temporary = await _temporaryDirectory();
    return File(p.join(
      temporary.path,
      'persian_transcriber',
      'captures',
      captureId,
      'capture.wav',
    ));
  }

  Future<Directory> _jobsRoot() async {
    final temporary = await _temporaryDirectory();
    return Directory(p.join(
      temporary.path,
      'persian_transcriber',
      'jobs',
    ));
  }

  Future<Directory> _jobDirectory(String jobId) async {
    final root = await _jobsRoot();
    return Directory(p.join(root.path, jobId));
  }

  Future<void> _deleteJobDirectory(String jobId) async {
    final directory = await _jobDirectory(jobId);
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (!await directory.exists()) return;
        await directory.delete(recursive: true);
        return;
      } on FileSystemException {
        if (attempt == 2) {
          throw const EngineFailure(
            EngineFailureCode.ioError,
            'Temporary prepared audio could not be removed.',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  Future<void> _deleteJobDirectoryQuietly(String jobId) async {
    try {
      await _deleteJobDirectory(jobId);
    } on EngineFailure {
      // The next job scope or the startup sweep can retry.
    }
  }

  Future<DateTime> _jobLastActivity(Directory directory) async {
    DateTime? newest;
    await for (final entity in directory.list(followLinks: false)) {
      try {
        final stat = await entity.stat();
        if (newest == null || stat.modified.isAfter(newest)) {
          newest = stat.modified;
        }
      } on FileSystemException {
        // Ignore an entry that disappeared during the sweep.
      }
    }
    if (newest != null) return newest;
    return (await directory.stat()).modified;
  }

  Future<FileStat?> _statOrNull(File file) async {
    try {
      return await FileStat.stat(file.path);
    } on FileSystemException {
      return null;
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw const EngineFailure(
        EngineFailureCode.disposed,
        'Audio preparation is disposed.',
      );
    }
  }

  String _requireId(String value, String label) {
    if (!_idPattern.hasMatch(value)) {
      throw EngineFailure(
        EngineFailureCode.invalidRequest,
        'Invalid $label identifier.',
      );
    }
    return value;
  }
}

final _idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');

final class _PreparationWorkerClient {
  _PreparationWorkerClient._({
    required this.isolate,
    required this.commands,
    required this.messages,
    required this.errors,
    required this.exits,
    required Map<String, Completer<_PreparationOutcome>> pending,
    required Completer<void> exit,
  })  : _pending = pending,
        _exit = exit;

  final Isolate isolate;
  final SendPort commands;
  final ReceivePort messages;
  final ReceivePort errors;
  final ReceivePort exits;
  final Map<String, Completer<_PreparationOutcome>> _pending;
  final Completer<void> _exit;
  bool _closing = false;

  bool get isAlive => !_closing && !_exit.isCompleted;

  static Future<_PreparationWorkerClient> spawn(
    FfmpegToolchainConfig config,
  ) async {
    final messages = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final pending = <String, Completer<_PreparationOutcome>>{};
    final started = Completer<SendPort>();
    final exit = Completer<void>();

    void failPending(EngineFailure failure) {
      final snapshot = List<Completer<_PreparationOutcome>>.of(
        pending.values,
      );
      pending.clear();
      for (final completer in snapshot) {
        if (!completer.isCompleted) {
          completer.complete(
            _PreparationFailed(failure.code, failure.message),
          );
        }
      }
    }

    final isolate = await Isolate.spawn<_WorkerBootstrap>(
      _workerMain,
      _WorkerBootstrap(messages.sendPort, config),
      onError: errors.sendPort,
      onExit: exits.sendPort,
      debugName: 'persian-transcriber-ffmpeg',
    );

    messages.listen((message) {
      switch (message) {
        case _WorkerStarted():
          if (!started.isCompleted) started.complete(message.commands);
        case _WorkerCompleted():
          pending.remove(message.requestId)?.complete(_PreparationCompleted(
                Duration(microseconds: message.durationMicros),
              ));
        case _WorkerFailed():
          pending.remove(message.requestId)?.complete(
                _PreparationFailed(
                  _decodeFailureCode(message.code),
                  message.message,
                ),
              );
        case _WorkerCancelled():
          pending.remove(message.requestId)?.complete(
                const _PreparationFailed(
                  EngineFailureCode.cancelled,
                  'Audio preparation was cancelled.',
                ),
              );
        default:
          // Ignore messages from a future worker version.
          break;
      }
    });

    errors.listen((dynamic _) {
      failPending(
        const EngineFailure(
          EngineFailureCode.ioError,
          'The FFmpeg preparation worker stopped unexpectedly.',
        ),
      );
    });
    exits.listen((dynamic _) {
      if (!exit.isCompleted) exit.complete();
      if (!started.isCompleted) {
        started.completeError(
          const AudioProcessException(
            'The FFmpeg preparation worker exited before it was ready.',
          ),
        );
      }
      failPending(
        const EngineFailure(
          EngineFailureCode.ioError,
          'The FFmpeg preparation worker exited unexpectedly.',
        ),
      );
    });

    try {
      final commands = await started.future.timeout(
        const Duration(seconds: 10),
      );
      return _PreparationWorkerClient._(
        isolate: isolate,
        commands: commands,
        messages: messages,
        errors: errors,
        exits: exits,
        pending: pending,
        exit: exit,
      );
    } on Object {
      isolate.kill(priority: Isolate.immediate);
      messages.close();
      errors.close();
      exits.close();
      rethrow;
    }
  }

  Future<_PreparationOutcome> request({
    required String requestId,
    required String sourcePath,
    required String outputPath,
  }) {
    if (!isAlive) {
      return Future<_PreparationOutcome>.error(
        const EngineFailure(
          EngineFailureCode.ioError,
          'The FFmpeg preparation worker is not running.',
        ),
      );
    }
    final completer = Completer<_PreparationOutcome>();
    _pending[requestId] = completer;
    commands.send(
      _WorkerPrepare(
        requestId: requestId,
        sourcePath: sourcePath,
        outputPath: outputPath,
      ),
    );
    return completer.future;
  }

  void cancel(String requestId) {
    if (!isAlive) return;
    commands.send(_WorkerCancel(requestId));
  }

  Future<void> shutdown() async {
    if (_closing) {
      await _exit.future;
      return;
    }
    _closing = true;
    try {
      commands.send(const _WorkerShutdown());
    } on Object {
      // The worker may already have exited.
    }
    try {
      await _exit.future.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      isolate.kill(priority: Isolate.immediate);
    } finally {
      messages.close();
      errors.close();
      exits.close();
      _pending.clear();
    }
  }
}

EngineFailureCode _decodeFailureCode(String name) {
  for (final code in EngineFailureCode.values) {
    if (code.name == name) return code;
  }
  return EngineFailureCode.unknown;
}

void _workerMain(_WorkerBootstrap bootstrap) {
  unawaited(_runWorker(bootstrap));
}

Future<void> _runWorker(_WorkerBootstrap bootstrap) async {
  final port = ReceivePort();
  final toolchain = FfmpegToolchain(config: bootstrap.config);
  final active = <String, _WorkerCancellation>{};
  var shuttingDown = false;

  void maybeClose() {
    if (shuttingDown && active.isEmpty) port.close();
  }

  port.listen((message) {
    switch (message) {
      case _WorkerPrepare(
          :final requestId,
          :final sourcePath,
          :final outputPath,
        ):
        if (shuttingDown) {
          bootstrap.parent.send(
            _WorkerFailed(
              requestId,
              EngineFailureCode.disposed.name,
              'The preparation worker is shutting down.',
            ),
          );
          return;
        }
        if (active.containsKey(requestId)) {
          bootstrap.parent.send(
            _WorkerFailed(
              requestId,
              EngineFailureCode.busy.name,
              'A preparation request with this ID is already active.',
            ),
          );
          return;
        }
        final cancellation = _WorkerCancellation();
        active[requestId] = cancellation;
        unawaited(
          _prepareInWorker(
            parent: bootstrap.parent,
            toolchain: toolchain,
            requestId: requestId,
            sourcePath: sourcePath,
            outputPath: outputPath,
            cancellation: cancellation,
          ).whenComplete(() {
            active.remove(requestId);
            maybeClose();
          }),
        );
      case _WorkerCancel(:final requestId):
        active[requestId]?.cancel();
      case _WorkerShutdown():
        shuttingDown = true;
        for (final cancellation in active.values) {
          cancellation.cancel();
        }
        maybeClose();
    }
  });

  bootstrap.parent.send(_WorkerStarted(port.sendPort));
}

Future<void> _prepareInWorker({
  required SendPort parent,
  required FfmpegToolchain toolchain,
  required String requestId,
  required String sourcePath,
  required String outputPath,
  required _WorkerCancellation cancellation,
}) async {
  final partPath = '$outputPath.part';
  try {
    _deleteQuietly(partPath);
    final format = await toolchain.convertToPcmWav(
      sourcePath: sourcePath,
      outputPath: partPath,
      cancellation: cancellation,
    );
    cancellation.throwIfCancelled();

    final part = File(partPath);
    if (!part.existsSync()) {
      throw const FormatException('FFmpeg did not write the prepared WAV.');
    }
    final output = File(outputPath);
    if (output.existsSync()) output.deleteSync();
    part.renameSync(outputPath);

    parent.send(
      _WorkerCompleted(requestId, format.duration.inMicroseconds),
    );
  } on EngineFailure catch (error) {
    _deleteQuietly(partPath);
    _deleteQuietly(outputPath);
    if (cancellation.isCancelled || error.code == EngineFailureCode.cancelled) {
      parent.send(_WorkerCancelled(requestId));
    } else {
      parent.send(_WorkerFailed(requestId, error.code.name, error.message));
    }
  } on FormatException catch (error) {
    _deleteQuietly(partPath);
    _deleteQuietly(outputPath);
    parent.send(
      _WorkerFailed(
        requestId,
        EngineFailureCode.invalidAudio.name,
        'Prepared audio failed validation: ${error.message}',
      ),
    );
  } on FileSystemException {
    _deleteQuietly(partPath);
    _deleteQuietly(outputPath);
    parent.send(
      _WorkerFailed(
        requestId,
        EngineFailureCode.ioError.name,
        'Prepared audio could not be stored.',
      ),
    );
  } on Object {
    _deleteQuietly(partPath);
    _deleteQuietly(outputPath);
    parent.send(
      _WorkerFailed(
        requestId,
        EngineFailureCode.unknown.name,
        'Audio preparation failed inside the FFmpeg worker.',
      ),
    );
  }
}

void _deleteQuietly(String path) {
  try {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  } on FileSystemException {
    // The parent cleanup owns the managed job directory.
  }
}

final class _WorkerCancellation implements CancellationSignal {
  final _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  @override
  void throwIfCancelled() {
    if (isCancelled) {
      throw const EngineFailure(
        EngineFailureCode.cancelled,
        'Audio preparation was cancelled.',
      );
    }
  }
}

final class _WorkerBootstrap {
  const _WorkerBootstrap(this.parent, this.config);

  final SendPort parent;
  final FfmpegToolchainConfig config;
}

sealed class _WorkerCommand {
  const _WorkerCommand();
}

final class _WorkerPrepare extends _WorkerCommand {
  const _WorkerPrepare({
    required this.requestId,
    required this.sourcePath,
    required this.outputPath,
  });

  final String requestId;
  final String sourcePath;
  final String outputPath;
}

final class _WorkerCancel extends _WorkerCommand {
  const _WorkerCancel(this.requestId);

  final String requestId;
}

final class _WorkerShutdown extends _WorkerCommand {
  const _WorkerShutdown();
}

sealed class _WorkerMessage {
  const _WorkerMessage();
}

final class _WorkerStarted extends _WorkerMessage {
  const _WorkerStarted(this.commands);

  final SendPort commands;
}

final class _WorkerCompleted extends _WorkerMessage {
  const _WorkerCompleted(this.requestId, this.durationMicros);

  final String requestId;
  final int durationMicros;
}

final class _WorkerFailed extends _WorkerMessage {
  const _WorkerFailed(this.requestId, this.code, this.message);

  final String requestId;
  final String code;
  final String message;
}

final class _WorkerCancelled extends _WorkerMessage {
  const _WorkerCancelled(this.requestId);

  final String requestId;
}

sealed class _PreparationOutcome {
  const _PreparationOutcome();
}

final class _PreparationCompleted extends _PreparationOutcome {
  const _PreparationCompleted(this.duration);

  final Duration duration;
}

final class _PreparationFailed extends _PreparationOutcome {
  const _PreparationFailed(this.code, this.message);

  final EngineFailureCode code;
  final String message;
}
