import 'dart:async';
import 'dart:io';

import 'package:client/features/transcriber/domain/ports/cancellation_signal.dart';
import 'package:client/platform/audio/audio_process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  if (!Platform.isWindows) {
    test(
      'SystemAudioProcessRunner integration tests require Windows',
      () {},
      skip: 'Windows command-processor tests',
    );
    return;
  }

  const runner = SystemAudioProcessRunner();
  final commandProcessor = Platform.environment['COMSPEC'] ??
      p.join(
        Platform.environment['SystemRoot'] ?? r'C:\Windows',
        'System32',
        'cmd.exe',
      );

  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('audio-runner-');
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('runs an explicit absolute executable without a shell', () async {
    final result = await runner.run(
      AudioProcessRequest(
        executablePath: commandProcessor,
        arguments: <String>['/d', '/c', 'echo', 'hello'],
      ),
      cancellation: _Cancellation(),
    );

    expect(result.succeeded, isTrue);
    expect(result.exitCode, 0);
    expect(result.cancelled, isFalse);
    expect(result.timedOut, isFalse);
  });

  test('captures a bounded stderr tail', () async {
    final script = File(p.join(temporary.path, 'noisy.bat'));
    await script.writeAsString(
      '@echo off\r\n'
      'for /l %%i in (1,1,200) do @echo 0123456789 1>&2\r\n',
    );

    final result = await runner.run(
      AudioProcessRequest(
        executablePath: commandProcessor,
        arguments: <String>['/d', '/c', script.path],
        maxStderrBytes: 64,
      ),
      cancellation: _Cancellation(),
    );

    expect(result.exitCode, 0);
    expect(result.stderr, isNotEmpty);
    expect(result.stderr.length, lessThanOrEqualTo(64));
  });

  test('reports a nonzero exit code', () async {
    final result = await runner.run(
      AudioProcessRequest(
        executablePath: commandProcessor,
        arguments: <String>['/d', '/c', 'exit', '3'],
      ),
      cancellation: _Cancellation(),
    );

    expect(result.exitCode, 3);
    expect(result.succeeded, isFalse);
  });

  test('cancellation terminates the process promptly', () async {
    final cancellation = _Cancellation();
    final stopwatch = Stopwatch()..start();
    final pending = runner.run(
      AudioProcessRequest(
        executablePath: commandProcessor,
        arguments: <String>['/d', '/c', 'pause'],
        timeout: const Duration(seconds: 30),
      ),
      cancellation: cancellation,
    );

    await Future<void>.delayed(const Duration(milliseconds: 150));
    cancellation.cancel();
    final result = await pending;
    stopwatch.stop();

    expect(result.cancelled, isTrue);
    expect(result.succeeded, isFalse);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('a timeout terminates the process', () async {
    final stopwatch = Stopwatch()..start();
    final result = await runner.run(
      AudioProcessRequest(
        executablePath: commandProcessor,
        arguments: <String>['/d', '/c', 'pause'],
        timeout: const Duration(milliseconds: 150),
      ),
      cancellation: _Cancellation(),
    );
    stopwatch.stop();

    expect(result.timedOut, isTrue);
    expect(result.succeeded, isFalse);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('an already-cancelled request never starts the process', () async {
    final cancellation = _Cancellation()..cancel();

    final result = await runner.run(
      AudioProcessRequest(
        executablePath: commandProcessor,
        arguments: <String>['/d', '/c', 'echo', 'must-not-run'],
      ),
      cancellation: cancellation,
    );

    expect(result.cancelled, isTrue);
    expect(result.exitCode, -1);
  });

  test('rejects a bare command name instead of searching PATH', () async {
    await expectLater(
      runner.run(
        AudioProcessRequest(
          executablePath: Platform.isWindows ? 'cmd.exe' : 'sh',
          arguments: const <String>['/c', 'exit', '0'],
        ),
        cancellation: _Cancellation(),
      ),
      throwsA(isA<AudioProcessException>()),
    );
  });

  test('rejects a missing absolute executable', () async {
    await expectLater(
      runner.run(
        AudioProcessRequest(
          executablePath: p.join(temporary.path, 'does-not-exist.exe'),
          arguments: const <String>[],
        ),
        cancellation: _Cancellation(),
      ),
      throwsA(isA<AudioProcessException>()),
    );
  });
}

final class _Cancellation implements CancellationSignal {
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
    if (isCancelled) throw StateError('cancelled');
  }
}
