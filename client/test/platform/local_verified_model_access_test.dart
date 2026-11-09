import 'dart:io';

import 'package:client/features/transcriber/domain/engine/abstract_engine_interface.dart';
import 'package:client/platform/models/local_verified_model_access.dart';
import 'package:client/platform/models/model_manifest.dart';
import 'package:client/platform/models/model_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/model_fixtures.dart';

void main() {
  late Directory root;
  late ModelStorage storage;
  final bytes = List<int>.generate(128, (index) => index);
  late final artifact =
      artifactFixture(byteLength: bytes.length, sha256: sha256Of(bytes));

  setUp(() async {
    root = await createModelRoot();
    storage = ModelStorage(rootDirectory: () async => root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  LocalVerifiedModelAccess access({String? manifest}) =>
      LocalVerifiedModelAccess(
        manifestLoader: () async =>
            ModelManifest.parse(manifest ?? manifestJson([artifact])),
        storage: storage,
        engine: ModelEngine.nativeFfi,
      );

  test('returns a verified spec for the installed artifact', () async {
    await installBytes(storage, artifact, bytes);

    final spec = await access()
        .resolveVerified(ModelTier.fast, cancellation: TestCancellation());

    expect(spec.id, artifact.id);
    expect(spec.artifactId, artifact.id);
    expect(spec.tier, ModelTier.fast);
  });

  test('reports modelUnavailable when the artifact is not installed', () async {
    await expectLater(
      access()
          .resolveVerified(ModelTier.fast, cancellation: TestCancellation()),
      throwsA(isA<EngineFailure>().having(
          (error) => error.code, 'code', EngineFailureCode.modelUnavailable)),
    );
  });

  test('reports modelUnavailable when the installed artifact is corrupt',
      () async {
    await installBytes(storage, artifact, bytes.sublist(1));

    await expectLater(
      access()
          .resolveVerified(ModelTier.fast, cancellation: TestCancellation()),
      throwsA(isA<EngineFailure>().having(
          (error) => error.code, 'code', EngineFailureCode.modelUnavailable)),
    );
  });

  test('reports modelUnavailable when no profile matches the platform',
      () async {
    final manifest = manifestJson([
      artifactFixture(
        id: 'wasm-only',
        byteLength: bytes.length,
        sha256: sha256Of(bytes),
        engines: const {ModelEngine.wasmWorker},
      ),
    ]);

    await expectLater(
      access(manifest: manifest)
          .resolveVerified(ModelTier.fast, cancellation: TestCancellation()),
      throwsA(isA<EngineFailure>().having(
          (error) => error.code, 'code', EngineFailureCode.modelUnavailable)),
    );
  });

  test('normalizes invalid manifests into a typed failure', () async {
    await expectLater(
      access(manifest: '{"schemaVersion": 1, "models": "nope"}')
          .resolveVerified(ModelTier.fast, cancellation: TestCancellation()),
      throwsA(isA<EngineFailure>().having(
          (error) => error.code, 'code', EngineFailureCode.modelUnavailable)),
    );
  });

  test('observes cancellation before resolving', () async {
    final cancellation = TestCancellation()..cancel();

    await expectLater(
      access().resolveVerified(ModelTier.fast, cancellation: cancellation),
      throwsA(isA<EngineFailure>()
          .having((error) => error.code, 'code', EngineFailureCode.cancelled)),
    );
  });
}
