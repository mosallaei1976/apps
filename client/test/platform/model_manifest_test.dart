import 'dart:convert';
import 'dart:io';

import 'package:client/features/transcriber/domain/engine/engine_types.dart';
import 'package:client/platform/models/model_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/model_fixtures.dart';

void main() {
  final bytes = List<int>.generate(32, (index) => index);
  final artifact = artifactFixture(
    byteLength: bytes.length,
    sha256: sha256Of(bytes),
  );

  test('parses a released artifact and selects it per tier and engine', () {
    final manifest = ModelManifest.parse(manifestJson([artifact]));

    expect(manifest.models, hasLength(1));
    final fast = manifest.artifactFor(ModelTier.fast, ModelEngine.nativeFfi);
    expect(fast?.id, artifact.id);
    expect(fast?.sha256, artifact.sha256);
    expect(fast?.byteLength, artifact.byteLength);
    expect(manifest.artifactFor(ModelTier.balanced, ModelEngine.nativeFfi),
        isNull);
    expect(
        manifest.artifactFor(ModelTier.fast, ModelEngine.wasmWorker), isNull);
  });

  test('converts manifest identity into the canonical engine spec', () {
    final spec = artifact.toSpec();

    expect(spec.id, artifact.id);
    expect(spec.artifactId, artifact.id);
    expect(spec.tier, ModelTier.fast);
    expect(spec.quantization, ModelQuantization.q5_1);
  });

  test('normalizes the SHA-256 digest to lowercase', () {
    final manifest = ModelManifest.parse(manifestJson([
      artifactFixture(
        byteLength: 1,
        sha256: 'A' * 64,
      ),
    ]));

    expect(manifest.models.single.sha256, 'a' * 64);
  });

  test('bundled manifest pins the released Fast and Balanced profiles',
      () async {
    final source = await File('assets/models/manifest.json').readAsString();
    final manifest = ModelManifest.parse(source);

    expect(manifest.models, hasLength(2));
    final fast = manifest.artifactFor(ModelTier.fast, ModelEngine.nativeFfi)!;
    expect(fast.id, 'whisper-base-q8-0');
    expect(fast.family, ModelFamily.base);
    expect(fast.quantization, ModelQuantization.q8_0);
    expect(fast.byteLength, 81768585);
    expect(fast.sha256,
        'c577b9a86e7e048a0b7eada054f4dd79a56bbfa911fbdacf900ac5b567cbb7d9');
    expect(fast.license, 'MIT');
    expect(fast.source.host, 'huggingface.co');
    expect(fast.source.path, contains('/ggml-base-q8_0.bin'));

    final balanced =
        manifest.artifactFor(ModelTier.balanced, ModelEngine.nativeFfi)!;
    expect(balanced.id, 'whisper-small-q5-1');
    expect(balanced.family, ModelFamily.small);
    expect(balanced.quantization, ModelQuantization.q5_1);
    expect(balanced.byteLength, 190085487);
    expect(balanced.sha256,
        'ae85e4a935d7a567bd102fe55afc16bb595bdb618e11b2fc7591bc08120411bb');
    expect(balanced.license, 'MIT');
    expect(balanced.source.path, contains('/ggml-small-q5_1.bin'));

    expect(
        manifest.artifactFor(ModelTier.fast, ModelEngine.wasmWorker), isNull);
    expect(manifest.artifactFor(ModelTier.balanced, ModelEngine.wasmWorker),
        isNull);
  });

  test('bundled manifest matches the pinned model source of truth', () async {
    final pins = jsonDecode(
      await File('tool/model_pins.json').readAsString(),
    ) as Map<String, dynamic>;
    final upstream = pins['upstream']! as Map<String, dynamic>;
    final models = pins['models']! as List<dynamic>;
    final manifest = ModelManifest.parse(
      await File('assets/models/manifest.json').readAsString(),
    );

    expect(manifest.models, hasLength(models.length));
    for (final raw in models) {
      final pin = raw! as Map<String, dynamic>;
      final tier = ModelTier.values.singleWhere(
        (value) => value.name == pin['tier'],
      );
      final artifact = manifest.artifactFor(tier, ModelEngine.nativeFfi)!;
      expect(artifact.id, pin['id']);
      expect(artifact.byteLength, pin['byteLength']);
      expect(artifact.sha256, pin['sha256']);
      expect(artifact.license, pin['license']);
      expect(
        artifact.source.toString(),
        'https://huggingface.co/${upstream['repository']}/resolve/'
        '${upstream['revision']}/${pin['file']}',
      );
    }
  });

  test('rejects unsupported schema versions', () {
    final source = jsonEncode({
      'schemaVersion': 2,
      'models': [artifactJson(artifact)],
    });

    expect(
      () => ModelManifest.parse(source),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects duplicate artifact IDs and duplicate tier profiles', () {
    expect(
      () => ModelManifest([artifact, artifact]),
      throwsA(isA<ArgumentError>()),
    );

    final duplicateProfile = artifactFixture(
      id: 'another-base',
      byteLength: 1,
      sha256: 'b' * 64,
    );
    expect(
      () => ModelManifest([artifact, duplicateProfile]),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects invalid artifact identity fields', () {
    expect(
      () => artifactFixture(byteLength: 0, sha256: 'a' * 64),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => artifactFixture(byteLength: 1, sha256: 'not-a-digest'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => artifactFixture(
        byteLength: 1,
        sha256: 'a' * 64,
        source: 'http://models.example.invalid/model.bin',
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => artifactFixture(
        byteLength: 1,
        sha256: 'a' * 64,
        engines: const {},
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects a profile whose family does not match its tier', () {
    expect(
      () => artifactFixture(
        tier: ModelTier.fast,
        family: ModelFamily.small,
        byteLength: 1,
        sha256: 'a' * 64,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects unknown enum values and malformed entries', () {
    final unknownEngine = artifactJson(artifact)
      ..['engines'] = ['browserWorker'];
    expect(
      () => ModelManifest.parse(jsonEncode({
        'schemaVersion': 1,
        'models': [unknownEngine],
      })),
      throwsA(isA<FormatException>()),
    );

    final missingLength = artifactJson(artifact)..remove('byteLength');
    expect(
      () => ModelManifest.parse(jsonEncode({
        'schemaVersion': 1,
        'models': [missingLength],
      })),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects legacy or unknown quantization labels', () {
    for (final label in ['int8', 'q5_k', 'q4_0']) {
      final entry = artifactJson(artifact)..['quantization'] = label;
      expect(
        () => ModelManifest.parse(jsonEncode({
          'schemaVersion': 1,
          'models': [entry],
        })),
        throwsA(isA<FormatException>()),
        reason: 'quantization $label must fail closed',
      );
    }
  });
}
