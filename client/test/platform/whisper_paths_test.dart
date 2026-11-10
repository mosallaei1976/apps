import 'dart:io';

import 'package:client/features/transcriber/domain/engine/engine_failure.dart';
import 'package:client/features/transcriber/domain/engine/engine_types.dart';
import 'package:client/platform/whisper/whisper_paths.dart';
import 'package:client/platform/whisper/whisper_toolchain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory appSupport;
  late Directory temporary;

  setUp(() async {
    appSupport = await Directory.systemTemp.createTemp('whisper-paths-app-');
    temporary = await Directory.systemTemp.createTemp('whisper-paths-temp-');
  });

  tearDown(() async {
    if (await appSupport.exists()) await appSupport.delete(recursive: true);
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  WhisperPathResolver resolver() => WhisperPathResolver(
        applicationSupportDirectory: () async => appSupport,
        temporaryDirectory: () async => temporary,
      );

  test('prefers an explicit absolute library path', () async {
    final explicit = p.join(temporary.path, 'custom', 'libwhisper.so');
    final config = WhisperToolchainConfig(
      libraryPath: explicit,
      expectedSha256: 'a' * 64,
    );

    expect(await resolver().libraryPath(config), explicit);
  });

  test('falls back to the managed library location without a path', () async {
    final config = WhisperToolchainConfig(expectedSha256: 'b' * 64);

    expect(
      await resolver().libraryPath(config),
      p.join(appSupport.path, 'whisper', 'whisper.dll'),
    );
  });

  test('resolves an installed model file and rejects missing or empty ones',
      () async {
    final model = ModelSpec(
      id: 'base-q8',
      tier: ModelTier.fast,
      artifactId: 'whisper-base-q8-0',
    );
    final file = File(
      p.join(appSupport.path, 'models', 'whisper-base-q8-0.bin'),
    );

    await expectLater(
      resolver().modelPath(model),
      throwsA(isA<EngineFailure>().having((failure) => failure.code, 'code',
          EngineFailureCode.modelUnavailable)),
    );

    await file.parent.create(recursive: true);
    await file.writeAsBytes(const [], flush: true);
    await expectLater(
      resolver().modelPath(model),
      throwsA(isA<EngineFailure>()),
    );

    await file.writeAsBytes(const [1, 2, 3], flush: true);
    expect(await resolver().modelPath(model), file.path);
  });

  test('rejects model identifiers that could escape the managed root',
      () async {
    final model = ModelSpec(
      id: 'base-q8',
      tier: ModelTier.fast,
      artifactId: '../escape',
    );

    await expectLater(
      resolver().modelPath(model),
      throwsA(isA<EngineFailure>().having((failure) => failure.code, 'code',
          EngineFailureCode.modelUnavailable)),
    );
  });

  test('resolves prepared audio and rejects missing or unsafe IDs', () async {
    final audio = PreparedAudio(
      audioId: 'job-1',
      duration: const Duration(seconds: 1),
    );
    final file = File(
      p.join(temporary.path, 'persian_transcriber', 'jobs', 'job-1',
          'prepared.wav'),
    );

    await expectLater(
      resolver().preparedAudioPath(audio),
      throwsA(isA<EngineFailure>().having(
          (failure) => failure.code, 'code', EngineFailureCode.invalidAudio)),
    );

    await file.parent.create(recursive: true);
    await file.writeAsBytes(const [1], flush: true);
    expect(await resolver().preparedAudioPath(audio), file.path);

    await expectLater(
      resolver().preparedAudioPath(PreparedAudio(
        audioId: '../escape',
        duration: const Duration(seconds: 1),
      )),
      throwsA(isA<EngineFailure>()),
    );
  });
}
