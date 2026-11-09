import 'dart:async';
import 'dart:io';

import 'package:client/features/transcriber/domain/engine/engine_failure.dart';
import 'package:client/features/transcriber/domain/ports/cancellation_signal.dart';
import 'package:client/platform/audio/ffmpeg_toolchain.dart';
import 'package:client/platform/audio/wav_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/ffmpeg_test_support.dart';

void main() {
  late FakeFfmpeg fake;
  late Directory temporary;

  setUpAll(() async {
    fake = await compileFakeFfmpeg();
  });

  tearDownAll(() async {
    await fake.dispose();
  });

  setUp(() async {
    await fake.clearControls();
    temporary = await Directory.systemTemp.createTemp('ffmpeg-toolchain-');
  });

  tearDown(() async {
    await fake.clearControls();
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  FfmpegToolchainConfig config({
    String? executablePath,
    String? sha256,
    Duration conversionTimeout = const Duration(minutes: 15),
  }) {
    return FfmpegToolchainConfig(
      executablePath: executablePath ?? fake.executable.path,
      expectedSha256: sha256 ?? fake.sha256,
      conversionTimeout: conversionTimeout,
    );
  }

  File sourceFile(String name) {
    final file = File(p.join(temporary.path, name));
    return file;
  }

  test('verifies the binary, self-tests once and converts to canonical WAV',
      () async {
    final source = sourceFile('capture.bin');
    await source.writeAsBytes(<int>[1, 2, 3, 4]);
    final output = File(p.join(temporary.path, 'prepared.wav.part'));
    final toolchain = FfmpegToolchain(config: config());

    final format = await toolchain.convertToPcmWav(
      sourcePath: source.path,
      outputPath: output.path,
      cancellation: _Cancellation(),
    );

    expect(format.duration, const Duration(milliseconds: 100));
    expect(await output.exists(), isTrue);
    expect(WavFormat.read(output).duration, format.duration);

    final calls = (await fake.calls()).trim().split('\n');
    expect(calls, hasLength(2));
    expect(calls.first, contains('lavfi'));
    expect(calls.first, contains('pcm_s16le'));
    expect(calls.last, contains('-protocol_whitelist file'));
    expect(calls.last, contains('-map 0:a:0'));
    expect(calls.last, contains('-ac 1'));
    expect(calls.last, contains('-ar 16000'));
    expect(calls.last, contains('-c:a pcm_s16le'));
    expect(calls.last, isNot(contains('http')));
    expect(calls.last, isNot(contains('rtmp')));

    final secondOutput = File(p.join(temporary.path, 'second.wav.part'));
    await toolchain.convertToPcmWav(
      sourcePath: source.path,
      outputPath: secondOutput.path,
      cancellation: _Cancellation(),
    );
    final secondCalls = (await fake.calls()).trim().split('\n');
    expect(secondCalls, hasLength(3));
    expect(
      secondCalls.where((line) => line.contains('lavfi')),
      hasLength(1),
      reason: 'the capability self-test must be cached',
    );
  });

  test('rejects a binary whose SHA-256 does not match', () async {
    final source = sourceFile('capture.bin');
    await source.writeAsBytes(<int>[1]);
    final toolchain = FfmpegToolchain(
      config: config(sha256: List<String>.filled(64, '0').join()),
    );

    await expectLater(
      toolchain.convertToPcmWav(
        sourcePath: source.path,
        outputPath: p.join(temporary.path, 'out.wav'),
        cancellation: _Cancellation(),
      ),
      throwsA(isA<EngineFailure>().having(
        (error) => error.code,
        'code',
        EngineFailureCode.unsupported,
      )),
    );
    expect(await fake.calls(), isEmpty);
  });

  test('rejects a missing binary', () async {
    final toolchain = FfmpegToolchain(
      config: config(
        executablePath: p.join(temporary.path, 'missing-ffmpeg.exe'),
      ),
    );

    await expectLater(
      toolchain.ensureReady(cancellation: _Cancellation()),
      throwsA(isA<EngineFailure>().having(
        (error) => error.code,
        'code',
        EngineFailureCode.unsupported,
      )),
    );
    expect(await fake.calls(), isEmpty);
  });

  test('a failed capability self-test is reported as unsupported', () async {
    await fake.setFailure(7);
    final toolchain = FfmpegToolchain(config: config());

    await expectLater(
      toolchain.ensureReady(cancellation: _Cancellation()),
      throwsA(isA<EngineFailure>().having(
        (error) => error.code,
        'code',
        EngineFailureCode.unsupported,
      )),
    );
    final calls = await fake.calls();
    expect(calls, contains('lavfi'));
  });

  test('a conversion failure is typed and removes the partial output',
      () async {
    final source = sourceFile('capture.bin');
    await source.writeAsBytes(<int>[1]);
    final output = File(p.join(temporary.path, 'prepared.wav.part'));
    final toolchain = FfmpegToolchain(config: config());
    await toolchain.ensureReady(cancellation: _Cancellation());

    await fake.setFailure(9);
    await expectLater(
      toolchain.convertToPcmWav(
        sourcePath: source.path,
        outputPath: output.path,
        cancellation: _Cancellation(),
      ),
      throwsA(isA<EngineFailure>()
          .having((error) => error.code, 'code', EngineFailureCode.invalidAudio)
          .having((error) => error.message, 'message',
              contains('FFmpeg could not prepare the captured audio'))
          .having((error) => error.message.length, 'bounded message length',
              lessThan(1000))),
    );
    expect(await output.exists(), isFalse);
  });

  test('invalid output bytes are rejected and removed', () async {
    final source = sourceFile('capture.bin');
    await source.writeAsBytes(<int>[1]);
    final output = File(p.join(temporary.path, 'prepared.wav.part'));
    final toolchain = FfmpegToolchain(config: config());
    await toolchain.ensureReady(cancellation: _Cancellation());

    await fake.setInvalidWav();
    await expectLater(
      toolchain.convertToPcmWav(
        sourcePath: source.path,
        outputPath: output.path,
        cancellation: _Cancellation(),
      ),
      throwsA(isA<EngineFailure>().having(
        (error) => error.code,
        'code',
        EngineFailureCode.invalidAudio,
      )),
    );
    expect(await output.exists(), isFalse);
  });

  test('a conversion timeout is typed and kills the process', () async {
    final source = sourceFile('capture.bin');
    await source.writeAsBytes(<int>[1]);
    final output = File(p.join(temporary.path, 'prepared.wav.part'));
    final toolchain = FfmpegToolchain(
      config: config(conversionTimeout: const Duration(milliseconds: 150)),
    );
    await toolchain.ensureReady(cancellation: _Cancellation());
    await fake.setDelay(const Duration(seconds: 3));

    final stopwatch = Stopwatch()..start();
    await expectLater(
      toolchain.convertToPcmWav(
        sourcePath: source.path,
        outputPath: output.path,
        cancellation: _Cancellation(),
      ),
      throwsA(isA<EngineFailure>().having(
        (error) => error.code,
        'code',
        EngineFailureCode.processingTimeout,
      )),
    );
    stopwatch.stop();
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(await output.exists(), isFalse);
  });

  test('cancellation during conversion stops the local process', () async {
    final source = sourceFile('capture.bin');
    await source.writeAsBytes(<int>[1]);
    final output = File(p.join(temporary.path, 'prepared.wav.part'));
    final toolchain = FfmpegToolchain(config: config());
    await toolchain.ensureReady(cancellation: _Cancellation());
    await fake.setDelay(const Duration(seconds: 3));
    final cancellation = _Cancellation();

    final pending = toolchain.convertToPcmWav(
      sourcePath: source.path,
      outputPath: output.path,
      cancellation: cancellation,
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    cancellation.cancel();

    final stopwatch = Stopwatch()..start();
    await expectLater(
      pending,
      throwsA(isA<EngineFailure>().having(
        (error) => error.code,
        'code',
        EngineFailureCode.cancelled,
      )),
    );
    stopwatch.stop();
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(await output.exists(), isFalse);
  });

  test('cancellation before readiness never runs the binary', () async {
    final cancellation = _Cancellation()..cancel();
    final toolchain = FfmpegToolchain(config: config());

    await expectLater(
      toolchain.ensureReady(cancellation: cancellation),
      throwsA(isA<EngineFailure>().having(
        (error) => error.code,
        'code',
        EngineFailureCode.cancelled,
      )),
    );
    expect(await fake.calls(), isEmpty);
  });

  test('rejects replacing the source with the prepared output', () async {
    final source = sourceFile('capture.bin');
    await source.writeAsBytes(<int>[1]);
    final toolchain = FfmpegToolchain(config: config());

    await expectLater(
      toolchain.convertToPcmWav(
        sourcePath: source.path,
        outputPath: source.path,
        cancellation: _Cancellation(),
      ),
      throwsA(isA<EngineFailure>().having(
        (error) => error.code,
        'code',
        EngineFailureCode.invalidRequest,
      )),
    );
  });

  test('configuration requires an absolute path and a full SHA-256', () {
    expect(
      () => FfmpegToolchainConfig(
        executablePath: Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg',
        expectedSha256: fake.sha256,
      ),
      throwsArgumentError,
    );
    expect(
      () => FfmpegToolchainConfig(
        executablePath: fake.executable.path,
        expectedSha256: 'abc',
      ),
      throwsArgumentError,
    );
    expect(
      () => FfmpegToolchainConfig(
        executablePath: fake.executable.path,
        expectedSha256: fake.sha256,
        maxStderrBytes: 0,
      ),
      throwsArgumentError,
    );
  });

  test('environment configuration is all-or-nothing', () {
    expect(FfmpegToolchainConfig.fromEnvironment(<String, String>{}), isNull);

    final pathOnly = <String, String>{
      FfmpegToolchainConfig.executablePathEnvironmentVariable:
          fake.executable.path,
    };
    expect(
      () => FfmpegToolchainConfig.fromEnvironment(pathOnly),
      throwsFormatException,
    );

    final configured = FfmpegToolchainConfig.fromEnvironment(
      <String, String>{
        FfmpegToolchainConfig.executablePathEnvironmentVariable:
            fake.executable.path,
        FfmpegToolchainConfig.sha256EnvironmentVariable:
            fake.sha256.toUpperCase(),
      },
    );
    expect(configured, isNotNull);
    expect(configured!.expectedSha256, fake.sha256);
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
    if (isCancelled) {
      throw const EngineFailure(
        EngineFailureCode.cancelled,
        'Cancelled by test.',
      );
    }
  }
}
