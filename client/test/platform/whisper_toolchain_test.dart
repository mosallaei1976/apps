import 'dart:io';

import 'package:client/features/transcriber/domain/engine/engine_failure.dart';
import 'package:client/platform/audio/wav_format.dart';
import 'package:client/platform/whisper/whisper_pcm.dart';
import 'package:client/platform/whisper/whisper_toolchain.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/wav_fixture.dart';

void main() {
  group('WhisperToolchainConfig', () {
    test('is absent only when both environment variables are absent', () {
      expect(WhisperToolchainConfig.fromEnvironment(const {}), isNull);
    });

    test('accepts a digest-only app-relative managed location', () {
      final config = WhisperToolchainConfig.fromEnvironment({
        WhisperToolchainConfig.sha256EnvironmentVariable: 'A' * 64,
      });
      expect(config, isNotNull);
      expect(config!.libraryPath, isNull);
      expect(config.expectedSha256, 'a' * 64);
    });

    test('accepts an absolute explicit path with a digest', () {
      final path = p.join(Directory.systemTemp.path, 'whisper.dll');
      final config = WhisperToolchainConfig.fromEnvironment({
        WhisperToolchainConfig.pathEnvironmentVariable: path,
        WhisperToolchainConfig.sha256EnvironmentVariable: 'b' * 64,
      });
      expect(config!.libraryPath, path);
      expect(config.expectedSha256, 'b' * 64);
    });

    test('rejects relative paths, missing digests and malformed digests', () {
      expect(
        () => WhisperToolchainConfig(libraryPath: 'whisper.dll', expectedSha256: 'a' * 64),
        throwsArgumentError,
      );
      expect(
        () => WhisperToolchainConfig.fromEnvironment({
          WhisperToolchainConfig.pathEnvironmentVariable:
              p.join(Directory.systemTemp.path, 'whisper.dll'),
        }),
        throwsFormatException,
      );
      expect(
        () => WhisperToolchainConfig.fromEnvironment({
          WhisperToolchainConfig.sha256EnvironmentVariable: 'short',
        }),
        throwsArgumentError,
      );
    });
  });

  group('verifyWhisperLibrary', () {
    late Directory temporary;
    late File library;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('whisper-toolchain-');
      library = File(p.join(temporary.path, 'whisper.dll'));
      await library.writeAsBytes(List<int>.generate(64, (index) => index));
    });

    tearDown(() async {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });

    test('accepts a file with the exact digest', () async {
      final digest = sha256.convert(await library.readAsBytes()).toString();
      await verifyWhisperLibrary(
        path: library.path,
        expectedSha256: digest,
      );
    });

    test('rejects missing, empty, relative and modified libraries', () async {
      final digest = sha256.convert(await library.readAsBytes()).toString();
      await expectLater(
        verifyWhisperLibrary(
          path: p.join(temporary.path, 'missing.dll'),
          expectedSha256: digest,
        ),
        throwsA(isA<EngineFailure>()
            .having((failure) => failure.code, 'code',
                EngineFailureCode.unsupported)),
      );
      await library.writeAsBytes(const [], flush: true);
      await expectLater(
        verifyWhisperLibrary(
          path: library.path,
          expectedSha256: digest,
        ),
        throwsA(isA<EngineFailure>()),
      );
      await library.writeAsBytes(const [1, 2, 3], flush: true);
      await expectLater(
        verifyWhisperLibrary(
          path: library.path,
          expectedSha256: digest,
        ),
        throwsA(isA<EngineFailure>()),
      );
      await expectLater(
        verifyWhisperLibrary(
          path: 'whisper.dll',
          expectedSha256: digest,
        ),
        throwsA(isA<EngineFailure>()),
      );
      await expectLater(
        verifyWhisperLibrary(
          path: library.path,
          expectedSha256: 'not-a-digest',
        ),
        throwsA(isA<EngineFailure>()),
      );
    });
  });

  group('WhisperPcm', () {
    test('converts little-endian signed 16-bit samples to floats', () async {
      final temporary = await Directory.systemTemp.createTemp('whisper-pcm-');
      addTearDown(() async {
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });
      final file = File(p.join(temporary.path, 'prepared.wav'));
      final bytes = wavBytes(dataLength: 4);
      bytes[44] = 0x00;
      bytes[45] = 0x40; // 16384 -> 0.5
      bytes[46] = 0x00;
      bytes[47] = 0xc0; // -16384 -> -0.5
      await file.writeAsBytes(bytes, flush: true);

      final format = WavFormat.read(file);
      final samples = WhisperPcm.read(file, format);
      expect(samples, hasLength(2));
      expect(samples[0], 0.5);
      expect(samples[1], -0.5);
    });
  });
}
