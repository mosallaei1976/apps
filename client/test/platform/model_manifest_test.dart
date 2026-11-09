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
    expect(spec.quantization, ModelQuantization.q5K);
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

  test('bundled manifest stays valid and intentionally empty', () async {
    final source = await File('assets/models/manifest.json').readAsString();

    expect(ModelManifest.parse(source).models, isEmpty);
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
}
