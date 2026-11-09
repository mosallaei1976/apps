import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import '../../features/transcriber/domain/engine/engine_failure.dart';
import '../audio/wav_format.dart';
import 'whisper_bindings.dart';
import 'whisper_inference_runner.dart';
import 'whisper_pcm.dart';
import 'whisper_toolchain.dart';

/// Production runner: a long-lived worker isolate owns the native library,
/// loaded model and PCM buffers. Only JSON-like events cross to the UI isolate.
final class IsolateWhisperInferenceRunner implements WhisperInferenceRunner {
  _WhisperWorkerClient? _worker;
  Future<_WhisperWorkerClient>? _workerFuture;
  bool _disposed = false;
  Future<void>? _disposal;

  @override
  Future<void> initialize({
    required String libraryPath,
    required String expectedSha256,
  }) async {
    _ensureNotDisposed();
    final worker = await _ensureWorker();
    await worker.initialize(
      libraryPath: libraryPath,
      expectedSha256: expectedSha256,
    );
  }

  @override
  Future<void> loadModel({required String modelPath}) async {
    _ensureNotDisposed();
    final worker = await _ensureWorker();
    await worker.loadModel(modelPath);
  }

  @override
  Stream<WhisperInferenceEvent> transcribe(WhisperInferenceRequest request) {
    if (_disposed) {
      return Stream<WhisperInferenceEvent>.error(
        const EngineFailure(
          EngineFailureCode.disposed,
          'Whisper inference is disposed.',
        ),
      );
    }
    final pending = _ensureWorker();
    late StreamController<WhisperInferenceEvent> controller;
    controller = StreamController<WhisperInferenceEvent>(
      onListen: () async {
        try {
          final worker = await pending;
          worker.transcribe(request).listen(
            controller.add,
            onError: controller.addError,
            onDone: controller.close,
          );
        } on Object catch (error) {
          controller.addError(_asFailure(
            error,
            const EngineFailure(
              EngineFailureCode.ioError,
              'The whisper.cpp worker could not start.',
            ),
          ));
          await controller.close();
        }
      },
      onCancel: () {
        final worker = _worker;
        if (worker != null) {
          unawaited(worker.cancel(request.requestId));
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> cancel(String requestId) async {
    final worker = _worker;
    if (worker == null) return;
    await worker.cancel(requestId);
  }

  @override
  Future<void> unloadModel() async {
    final worker = _worker;
    if (worker == null) return;
    await worker.unloadModel();
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    final worker = _worker;
    _worker = null;
    final pending = _workerFuture;
    _workerFuture = null;
    if (worker != null) await worker.shutdown();
    if (pending != null) {
      try {
        final lateWorker = await pending;
        await lateWorker.shutdown();
      } on Object {
        // Spawn already failed; there is no worker to close.
      }
    }
  }

  Future<_WhisperWorkerClient> _ensureWorker() async {
    final existing = _worker;
    if (existing != null && existing.isAlive) return existing;
    if (existing != null) {
      _worker = null;
      await existing.shutdown();
    }

    final pending = _workerFuture ??= _WhisperWorkerClient.spawn();
    try {
      final client = await pending;
      if (!_disposed) _worker = client;
      return client;
    } on EngineFailure {
      rethrow;
    } on Object {
      throw const EngineFailure(
        EngineFailureCode.ioError,
        'The whisper.cpp inference worker could not start.',
      );
    } finally {
      if (identical(_workerFuture, pending)) _workerFuture = null;
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw const EngineFailure(
        EngineFailureCode.disposed,
        'Whisper inference is disposed.',
      );
    }
  }

  EngineFailure _asFailure(Object error, EngineFailure fallback) =>
      error is EngineFailure ? error : fallback;
}

final class _WhisperWorkerClient {
  _WhisperWorkerClient._({
    required this.isolate,
    required this.commands,
    required this.messages,
    required this.errors,
    required this.exits,
    required Map<String, Completer<void>> pendingCommands,
    required Map<String, StreamController<WhisperInferenceEvent>> pendingJobs,
    required Completer<void> exit,
  })  : _pendingCommands = pendingCommands,
        _pendingJobs = pendingJobs,
        _exit = exit;

  final Isolate isolate;
  final SendPort commands;
  final ReceivePort messages;
  final ReceivePort errors;
  final ReceivePort exits;
  final Map<String, Completer<void>> _pendingCommands;
  final Map<String, StreamController<WhisperInferenceEvent>> _pendingJobs;
  final Completer<void> _exit;
  int _sequence = 0;
  bool _closing = false;

  bool get isAlive => !_closing && !_exit.isCompleted;

  static Future<_WhisperWorkerClient> spawn() async {
    final messages = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final pendingCommands = <String, Completer<void>>{};
    final pendingJobs = <String, StreamController<WhisperInferenceEvent>>{};
    final started = Completer<SendPort>();
    final exit = Completer<void>();

    void failAll(EngineFailure failure) {
      final commands = List<Completer<void>>.of(pendingCommands.values);
      pendingCommands.clear();
      for (final completer in commands) {
        if (!completer.isCompleted) completer.completeError(failure);
      }
      final jobs = List<StreamController<WhisperInferenceEvent>>.of(
        pendingJobs.values,
      );
      pendingJobs.clear();
      for (final controller in jobs) {
        controller.addError(failure);
        unawaited(controller.close());
      }
    }

    final isolate = await Isolate.spawn<_WhisperWorkerBootstrap>(
      _whisperWorkerMain,
      _WhisperWorkerBootstrap(messages.sendPort),
      onError: errors.sendPort,
      onExit: exits.sendPort,
      debugName: 'persian-transcriber-whisper',
    );

    messages.listen((message) {
      switch (message) {
        case _WorkerStarted():
          if (!started.isCompleted) started.complete(message.commands);
        case _WorkerAck(:final requestId):
          pendingCommands.remove(requestId)?.complete();
        case _WorkerProgress(:final requestId, :final fraction):
          pendingJobs[requestId]?.add(WhisperInferenceProgress(fraction));
        case _WorkerSegments(:final requestId, :final segments):
          pendingJobs[requestId]?.add(WhisperInferenceSegments(segments));
        case _WorkerCompleted(:final requestId):
          final controller = pendingJobs.remove(requestId);
          if (controller != null) {
            controller.add(const WhisperInferenceCompleted());
            unawaited(controller.close());
          }
        case _WorkerCancelled(:final requestId):
          final controller = pendingJobs.remove(requestId);
          if (controller != null) {
            controller.add(const WhisperInferenceCancelled());
            unawaited(controller.close());
          }
        case _WorkerFailed(
            :final requestId,
            :final code,
            :final message,
          ):
          final failure = EngineFailure(_decodeCode(code), message);
          final command = pendingCommands.remove(requestId);
          if (command != null) {
            if (!command.isCompleted) command.completeError(failure);
          } else {
            final controller = pendingJobs.remove(requestId);
            if (controller != null) {
              controller.addError(failure);
              unawaited(controller.close());
            }
          }
      }
    });

    errors.listen((dynamic _) {
      failAll(const EngineFailure(
        EngineFailureCode.ioError,
        'The whisper.cpp worker stopped unexpectedly.',
      ));
    });
    exits.listen((dynamic _) {
      if (!exit.isCompleted) exit.complete();
      if (!started.isCompleted) {
        started.completeError(const EngineFailure(
          EngineFailureCode.ioError,
          'The whisper.cpp worker exited before it was ready.',
        ));
      }
      failAll(const EngineFailure(
        EngineFailureCode.ioError,
        'The whisper.cpp worker exited unexpectedly.',
      ));
    });

    try {
      final commandPort = await started.future.timeout(
        const Duration(seconds: 10),
      );
      return _WhisperWorkerClient._(
        isolate: isolate,
        commands: commandPort,
        messages: messages,
        errors: errors,
        exits: exits,
        pendingCommands: pendingCommands,
        pendingJobs: pendingJobs,
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

  Future<void> initialize({
    required String libraryPath,
    required String expectedSha256,
  }) {
    final requestId = _nextCommandId();
    return _command(
      requestId,
      _WorkerInitialize(requestId, libraryPath, expectedSha256),
    );
  }

  Future<void> loadModel(String modelPath) {
    final requestId = _nextCommandId();
    return _command(requestId, _WorkerLoadModel(requestId, modelPath));
  }

  Future<void> unloadModel() {
    final requestId = _nextCommandId();
    return _command(requestId, _WorkerUnloadModel(requestId));
  }

  Stream<WhisperInferenceEvent> transcribe(WhisperInferenceRequest request) {
    if (!isAlive) {
      return Stream<WhisperInferenceEvent>.error(
        const EngineFailure(
          EngineFailureCode.ioError,
          'The whisper.cpp inference worker is not running.',
        ),
      );
    }
    if (_pendingJobs.isNotEmpty) {
      return Stream<WhisperInferenceEvent>.error(
        const EngineFailure(
          EngineFailureCode.busy,
          'A whisper.cpp transcription is already active.',
        ),
      );
    }
    final controller = StreamController<WhisperInferenceEvent>();
    _pendingJobs[request.requestId] = controller;
    controller.onListen = () {
      commands.send(_WorkerTranscribe(
        request.requestId,
        request.audioPath,
        request.audioDuration.inMicroseconds,
        request.languageCode,
        request.emitPartials,
      ));
    };
    return controller.stream;
  }

  Future<void> cancel(String requestId) async {
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
      _pendingCommands.clear();
      _pendingJobs.clear();
    }
  }

  Future<void> _command(String requestId, Object message) {
    if (!isAlive) {
      return Future<void>.error(const EngineFailure(
        EngineFailureCode.ioError,
        'The whisper.cpp inference worker is not running.',
      ));
    }
    final completer = Completer<void>();
    _pendingCommands[requestId] = completer;
    commands.send(message);
    return completer.future;
  }

  String _nextCommandId() =>
      'whisper-command-${DateTime.now().toUtc().microsecondsSinceEpoch}-'
      '${_sequence++}';
}

EngineFailureCode _decodeCode(String name) {
  for (final code in EngineFailureCode.values) {
    if (code.name == name) return code;
  }
  return EngineFailureCode.unknown;
}

// Worker isolate ------------------------------------------------------------

void _whisperWorkerMain(_WhisperWorkerBootstrap bootstrap) {
  unawaited(_runWhisperWorker(bootstrap));
}

Future<void> _runWhisperWorker(_WhisperWorkerBootstrap bootstrap) async {
  final port = ReceivePort();
  final cancelled = <String>{};
  WhisperBindings? bindings;
  Pointer<WhisperContext>? context;
  String? activeRequestId;
  var shuttingDown = false;
  var initializing = false;
  var loadingModel = false;

  void closeIfIdle() {
    if (shuttingDown && activeRequestId == null && !initializing && !loadingModel) {
      port.close();
    }
  }

  void sendFailure(String requestId, EngineFailure failure) {
    bootstrap.parent.send(
      _WorkerFailed(requestId, failure.code.name, failure.message),
    );
  }

  void releaseContext() {
    final previous = context;
    context = null;
    final native = bindings;
    if (previous != null && native != null) {
      native.free(previous);
    }
  }

  Future<void> initialize(
    String requestId,
    String libraryPath,
    String expectedSha256,
  ) async {
    initializing = true;
    try {
      await verifyWhisperLibrary(
        path: libraryPath,
        expectedSha256: expectedSha256,
      );
      bindings = WhisperBindings.load(libraryPath);
      bootstrap.parent.send(_WorkerAck(requestId));
    } on EngineFailure catch (failure) {
      sendFailure(requestId, failure);
    } on Object {
      sendFailure(
        requestId,
        const EngineFailure(
          EngineFailureCode.unsupported,
          'The configured whisper.cpp library could not be loaded.',
        ),
      );
    } finally {
      initializing = false;
      closeIfIdle();
    }
  }

  Future<void> loadModel(String requestId, String modelPath) async {
    loadingModel = true;
    try {
      final native = bindings;
      if (native == null) {
        throw const EngineFailure(
          EngineFailureCode.initializationFailed,
          'The whisper.cpp runtime is not initialized.',
        );
      }
      releaseContext();
      final path = modelPath.toNativeUtf8();
      try {
        final params = native.contextDefaultParams();
        final loaded = native.initFromFileWithParams(path, params);
        if (loaded == nullptr) {
          throw const EngineFailure(
            EngineFailureCode.modelLoadFailed,
            'whisper.cpp could not load the verified model artifact.',
          );
        }
        context = loaded;
      } finally {
        malloc.free(path);
      }
      bootstrap.parent.send(_WorkerAck(requestId));
    } on EngineFailure catch (failure) {
      sendFailure(requestId, failure);
    } on Object {
      sendFailure(
        requestId,
        const EngineFailure(
          EngineFailureCode.modelLoadFailed,
          'whisper.cpp could not load the verified model artifact.',
        ),
      );
    } finally {
      loadingModel = false;
      closeIfIdle();
    }
  }

  void unloadModel(String requestId) {
    try {
      releaseContext();
      bootstrap.parent.send(_WorkerAck(requestId));
    } on Object {
      sendFailure(
        requestId,
        const EngineFailure(
          EngineFailureCode.ioError,
          'whisper.cpp could not release the model.',
        ),
      );
    }
  }

  port.listen((message) {
    switch (message) {
      case _WorkerInitialize(
          :final requestId,
          :final libraryPath,
          :final expectedSha256,
        ):
        if (shuttingDown) {
          sendFailure(
            requestId,
            const EngineFailure(
              EngineFailureCode.disposed,
              'The whisper.cpp worker is shutting down.',
            ),
          );
          return;
        }
        unawaited(initialize(requestId, libraryPath, expectedSha256));
      case _WorkerLoadModel(:final requestId, :final modelPath):
        if (shuttingDown) {
          sendFailure(
            requestId,
            const EngineFailure(
              EngineFailureCode.disposed,
              'The whisper.cpp worker is shutting down.',
            ),
          );
          return;
        }
        unawaited(loadModel(requestId, modelPath));
      case _WorkerUnloadModel(:final requestId):
        unloadModel(requestId);
      case _WorkerTranscribe(
          :final requestId,
          :final audioPath,
          :final durationMicros,
          :final languageCode,
          :final emitPartials,
        ):
        if (shuttingDown) {
          sendFailure(
            requestId,
            const EngineFailure(
              EngineFailureCode.disposed,
              'The whisper.cpp worker is shutting down.',
            ),
          );
          return;
        }
        if (activeRequestId != null) {
          sendFailure(
            requestId,
            const EngineFailure(
              EngineFailureCode.busy,
              'A whisper.cpp transcription is already active.',
            ),
          );
          return;
        }
        activeRequestId = requestId;
        unawaited(
          _transcribeInWorker(
            parent: bootstrap.parent,
            bindings: bindings,
            context: context,
            requestId: requestId,
            audioPath: audioPath,
            durationMicros: durationMicros,
            languageCode: languageCode,
            emitPartials: emitPartials,
            isCancelled: () =>
                shuttingDown || cancelled.contains(requestId),
          ).whenComplete(() {
            cancelled.remove(requestId);
            activeRequestId = null;
            closeIfIdle();
          }),
        );
      case _WorkerCancel(:final requestId):
        cancelled.add(requestId);
      case _WorkerShutdown():
        shuttingDown = true;
        final active = activeRequestId;
        if (active != null) cancelled.add(active);
        closeIfIdle();
    }
  });

  bootstrap.parent.send(_WorkerStarted(port.sendPort));
}

Future<void> _transcribeInWorker({
  required SendPort parent,
  required WhisperBindings? bindings,
  required Pointer<WhisperContext>? context,
  required String requestId,
  required String audioPath,
  required int durationMicros,
  required String languageCode,
  required bool emitPartials,
  required bool Function() isCancelled,
}) async {
  Pointer<Float>? samples;
  Pointer<Utf8>? language;
  try {
    final native = bindings;
    final nativeContext = context;
    if (native == null || nativeContext == null) {
      throw const EngineFailure(
        EngineFailureCode.notReady,
        'The whisper.cpp runtime or model is not ready.',
      );
    }
    if (!p.isAbsolute(audioPath)) {
      throw const EngineFailure(
        EngineFailureCode.invalidAudio,
        'Prepared audio must be an absolute local path.',
      );
    }

    final file = File(audioPath);
    final WavFormat format;
    try {
      format = WavFormat.read(file);
    } on FormatException catch (error) {
      throw EngineFailure(
        EngineFailureCode.invalidAudio,
        'Prepared audio failed validation: ${error.message}',
      );
    } on FileSystemException {
      throw const EngineFailure(
        EngineFailureCode.invalidAudio,
        'Prepared audio could not be read.',
      );
    }
    if (format.duration <= Duration.zero) {
      throw const EngineFailure(
        EngineFailureCode.invalidAudio,
        'Prepared audio has no positive duration.',
      );
    }

    final Float32List floats;
    try {
      floats = WhisperPcm.read(file, format);
    } on FormatException catch (error) {
      throw EngineFailure(
        EngineFailureCode.invalidAudio,
        'Prepared audio failed validation: ${error.message}',
      );
    } on FileSystemException {
      throw const EngineFailure(
        EngineFailureCode.ioError,
        'Prepared audio could not be read.',
      );
    }

    samples = calloc<Float>(floats.length);
    samples.asTypedList(floats.length).setAll(0, floats);
    language = languageCode.toNativeUtf8();
    final languagePointer = language;

    const int sampleRate = WavFormat.requiredSampleRate;
    const int chunkSamples = sampleRate * 30;
    final totalDurationMicros =
        durationMicros > 0 ? durationMicros : format.duration.inMicroseconds;
    var start = 0;
    var segmentSequence = 0;

    while (start < floats.length) {
      // Yield so cancellation and shutdown messages are processed between
      // decoder windows. whisper_full itself is a synchronous native call.
      await Future<void>.delayed(Duration.zero);
      if (isCancelled()) {
        parent.send(_WorkerCancelled(requestId));
        return;
      }

      final int count =
          math.min<int>(chunkSamples, floats.length - start);
      final params = native.fullDefaultParams(WhisperBindings.samplingGreedy);
      params.language = languagePointer;
      params.noContext = 1;
      params.printProgress = 0;
      params.printRealtime = 0;
      params.printTimestamps = 0;
      params.translate = 0;

      final result = native.full(
        nativeContext,
        params,
        samples + start,
        count,
      );
      if (isCancelled()) {
        parent.send(_WorkerCancelled(requestId));
        return;
      }
      if (result != 0) {
        throw const EngineFailure(
          EngineFailureCode.inferenceFailed,
          'whisper.cpp could not decode the prepared audio.',
        );
      }

      final segmentCount = native.fullNSegments(nativeContext);
      if (segmentCount < 0) {
        throw const EngineFailure(
          EngineFailureCode.inferenceFailed,
          'whisper.cpp returned an invalid segment count.',
        );
      }

      final chunkStart = _microsForSample(start, sampleRate);
      final chunkEnd = _microsForSample(start + count, sampleRate);
      final segments = <WhisperInferenceSegment>[];
      for (var index = 0; index < segmentCount; index++) {
        final textPointer = native.fullGetSegmentText(nativeContext, index);
        if (textPointer == nullptr) continue;
        final text = textPointer.toDartString().trim();
        if (text.isEmpty) continue;

        final rawStart = native.fullGetSegmentT0(nativeContext, index);
        final rawEnd = native.fullGetSegmentT1(nativeContext, index);
        if (rawStart < 0 || rawEnd < rawStart) continue;

        final segmentStart = chunkStart + rawStart * 10000;
        final rawSegmentEnd = chunkStart + rawEnd * 10000;
        final boundedEnd = math.min(rawSegmentEnd, math.min(chunkEnd, totalDurationMicros));
        if (segmentStart >= boundedEnd) continue;

        segments.add(WhisperInferenceSegment(
          segmentId: 'whisper-segment-${segmentSequence++}',
          text: text,
          start: Duration(microseconds: segmentStart),
          end: Duration(microseconds: boundedEnd),
        ));
      }
      if (segments.isNotEmpty) {
        parent.send(_WorkerSegments(requestId, segments));
      }

      final fraction =
          math.min(1.0, (start + count).toDouble() / floats.length);
      parent.send(_WorkerProgress(requestId, fraction));
      start += count;
    }

    parent.send(_WorkerProgress(requestId, 1.0));
    parent.send(_WorkerCompleted(requestId));
  } on EngineFailure catch (failure) {
    parent.send(
      _WorkerFailed(requestId, failure.code.name, failure.message),
    );
  } on Object {
    parent.send(_WorkerFailed(
      requestId,
      EngineFailureCode.inferenceFailed.name,
      'whisper.cpp inference failed inside the worker.',
    ));
  } finally {
    if (samples != null) calloc.free(samples);
    if (language != null) malloc.free(language);
  }
}

int _microsForSample(int sample, int sampleRate) =>
    (sample * Duration.microsecondsPerSecond) ~/ sampleRate;

final class _WhisperWorkerBootstrap {
  const _WhisperWorkerBootstrap(this.parent);

  final SendPort parent;
}

sealed class _WorkerCommand {
  const _WorkerCommand();
}

final class _WorkerInitialize extends _WorkerCommand {
  const _WorkerInitialize(this.requestId, this.libraryPath, this.expectedSha256);

  final String requestId;
  final String libraryPath;
  final String expectedSha256;
}

final class _WorkerLoadModel extends _WorkerCommand {
  const _WorkerLoadModel(this.requestId, this.modelPath);

  final String requestId;
  final String modelPath;
}

final class _WorkerUnloadModel extends _WorkerCommand {
  const _WorkerUnloadModel(this.requestId);

  final String requestId;
}

final class _WorkerTranscribe extends _WorkerCommand {
  const _WorkerTranscribe(
    this.requestId,
    this.audioPath,
    this.durationMicros,
    this.languageCode,
    this.emitPartials,
  );

  final String requestId;
  final String audioPath;
  final int durationMicros;
  final String languageCode;
  final bool emitPartials;
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

final class _WorkerAck extends _WorkerMessage {
  const _WorkerAck(this.requestId);

  final String requestId;
}

final class _WorkerProgress extends _WorkerMessage {
  const _WorkerProgress(this.requestId, this.fraction);

  final String requestId;
  final double fraction;
}

final class _WorkerSegments extends _WorkerMessage {
  const _WorkerSegments(this.requestId, this.segments);

  final String requestId;
  final List<WhisperInferenceSegment> segments;
}

final class _WorkerCompleted extends _WorkerMessage {
  const _WorkerCompleted(this.requestId);

  final String requestId;
}

final class _WorkerCancelled extends _WorkerMessage {
  const _WorkerCancelled(this.requestId);

  final String requestId;
}

final class _WorkerFailed extends _WorkerMessage {
  const _WorkerFailed(this.requestId, this.code, this.message);

  final String requestId;
  final String code;
  final String message;
}
