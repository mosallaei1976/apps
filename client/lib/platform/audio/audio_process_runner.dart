import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../features/transcriber/domain/ports/cancellation_signal.dart';

/// A process invocation with no shell, no PATH lookup and no network protocol.
///
/// The executable path must already be an absolute path to a local file. Callers
/// are responsible for verifying that file (for example with SHA-256) before
/// using it for untrusted media.
final class AudioProcessRequest {
  const AudioProcessRequest({
    required this.executablePath,
    required this.arguments,
    this.workingDirectory,
    this.maxStderrBytes = 8192,
    this.timeout,
  })  : assert(maxStderrBytes > 0),
        assert(timeout == null || timeout > Duration.zero);

  final String executablePath;
  final List<String> arguments;
  final String? workingDirectory;

  /// Upper bound for retained stderr bytes. FFmpeg diagnostics can be large;
  /// only the tail is useful when reporting a failure.
  final int maxStderrBytes;

  final Duration? timeout;
}

final class AudioProcessResult {
  const AudioProcessResult({
    required this.exitCode,
    required this.stderr,
    this.cancelled = false,
    this.timedOut = false,
  });

  final int exitCode;
  final String stderr;
  final bool cancelled;
  final bool timedOut;

  bool get succeeded => !cancelled && !timedOut && exitCode == 0;
}

final class AudioProcessException implements Exception {
  const AudioProcessException(this.message);

  final String message;

  @override
  String toString() => 'AudioProcessException: $message';
}

abstract interface class AudioProcessRunner {
  Future<AudioProcessResult> run(
    AudioProcessRequest request, {
    required CancellationSignal cancellation,
  });
}

/// Starts one local process directly with [Process.start].
///
/// Safety properties:
/// - [AudioProcessRequest.executablePath] must be absolute and point at a file;
///   a bare command name is rejected instead of being resolved through PATH.
/// - The process is started with `runInShell: false`.
/// - Stderr is retained in a bounded byte buffer. Stdout is drained, not kept.
/// - Cancellation and timeouts terminate the process and wait for it to exit.
final class SystemAudioProcessRunner implements AudioProcessRunner {
  const SystemAudioProcessRunner();

  @override
  Future<AudioProcessResult> run(
    AudioProcessRequest request, {
    required CancellationSignal cancellation,
  }) async {
    final executable = _validateExecutable(request.executablePath);
    if (request.maxStderrBytes <= 0) {
      throw const AudioProcessException(
        'The stderr capture limit must be positive.',
      );
    }
    if (request.timeout != null && request.timeout! <= Duration.zero) {
      throw const AudioProcessException(
          'The process timeout must be positive.');
    }
    if (cancellation.isCancelled) {
      return const AudioProcessResult(
        exitCode: -1,
        stderr: '',
        cancelled: true,
      );
    }

    final Process process;
    try {
      process = await Process.start(
        executable,
        request.arguments,
        workingDirectory: request.workingDirectory,
        runInShell: false,
      );
    } on ProcessException catch (error) {
      throw AudioProcessException(
        'The local audio process could not be started: ${error.message}',
      );
    } on FileSystemException catch (error) {
      throw AudioProcessException(
        'The local audio process could not be started: ${error.message}',
      );
    }

    final stderrBuffer = _BoundedBytes(request.maxStderrBytes);
    final stderrDone = Completer<void>();
    final stderrSubscription = process.stderr.listen(
      stderrBuffer.add,
      onError: (Object _) {},
      onDone: stderrDone.complete,
      cancelOnError: false,
    );
    final stdoutDone = process.stdout.drain<void>();

    var finished = false;
    var cancelled = false;
    var timedOut = false;

    final cancelListener = cancellation.whenCancelled.then((_) {
      if (finished) return;
      cancelled = true;
      _killQuietly(process);
    });

    Timer? timeoutTimer;
    final timeout = request.timeout;
    if (timeout != null) {
      timeoutTimer = Timer(timeout, () {
        if (finished) return;
        timedOut = true;
        _killQuietly(process);
      });
    }

    final exitCode = await process.exitCode;
    finished = true;
    timeoutTimer?.cancel();

    try {
      await stderrDone.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // A killed process should close stderr promptly. Do not let a broken
      // pipe keep a cancellation or failure from settling.
    }
    try {
      await stdoutDone.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // The process is already gone; the bounded diagnostics are still useful.
    }
    await stderrSubscription.cancel();

    if (cancellation.isCancelled) cancelled = true;
    // Keep the cancel listener alive until the result is built so a late
    // cancellation is observed, but do not leave an unhandled error behind.
    unawaited(cancelListener);

    return AudioProcessResult(
      exitCode: exitCode,
      stderr: stderrBuffer.text,
      cancelled: cancelled,
      timedOut: timedOut,
    );
  }

  String _validateExecutable(String value) {
    if (value.trim().isEmpty) {
      throw const AudioProcessException(
          'An explicit executable path is required.');
    }
    if (!p.isAbsolute(value)) {
      throw const AudioProcessException(
        'Audio executables must be addressed by an absolute path; PATH search is not allowed.',
      );
    }

    final type = FileSystemEntity.typeSync(value);
    if (type != FileSystemEntityType.file) {
      throw const AudioProcessException(
        'The configured local audio executable does not exist or is not a file.',
      );
    }
    return value;
  }

  void _killQuietly(Process process) {
    try {
      process.kill();
    } on Object {
      // The process may have exited between the check and the kill.
    }
  }
}

final class _BoundedBytes {
  _BoundedBytes(this._maxBytes) : assert(_maxBytes > 0);

  final int _maxBytes;
  final List<int> _bytes = [];

  void add(List<int> chunk) {
    if (chunk.length >= _maxBytes) {
      _bytes
        ..clear()
        ..addAll(chunk.sublist(chunk.length - _maxBytes));
      return;
    }
    final overflow = _bytes.length + chunk.length - _maxBytes;
    if (overflow > 0) _bytes.removeRange(0, overflow);
    _bytes.addAll(chunk);
  }

  String get text => utf8.decode(_bytes, allowMalformed: true);
}
