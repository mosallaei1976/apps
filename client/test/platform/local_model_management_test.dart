import 'dart:io';

import 'package:client/features/transcriber/domain/engine/engine_failure.dart';
import 'package:client/features/transcriber/domain/engine/engine_types.dart';
import 'package:client/features/transcriber/domain/ports/model_management.dart';
import 'package:client/platform/models/local_model_management.dart';
import 'package:client/platform/models/model_download.dart' as platform;
import 'package:client/platform/models/model_manifest.dart';
import 'package:client/platform/models/model_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/model_fixtures.dart';

final class _FakeTransport implements platform.ModelDownloadTransport {
  _FakeTransport(this.bytes);

  final List<int> bytes;
  final requests = <({Uri uri, int? rangeStart, String? ifRange})>[];

  @override
  Future<platform.ModelDownloadResponse> send(
    Uri uri, {
    int? rangeStart,
    String? ifRange,
  }) async {
    requests.add((uri: uri, rangeStart: rangeStart, ifRange: ifRange));
    return platform.ModelDownloadResponse(
      statusCode: 200,
      contentLength: bytes.length,
      body: Stream.value(bytes),
      abort: () async {},
    );
  }

  @override
  Future<void> close() async {}
}

void main() {
  late Directory root;
  late ModelStorage storage;
  late ModelArtifact fastArtifact;
  late ModelArtifact balancedArtifact;

  setUp(() async {
    root = await createModelRoot();
    storage = ModelStorage(rootDirectory: () async => root);
    fastArtifact = artifactFixture(
      id: 'whisper-base-q5',
      tier: ModelTier.fast,
      byteLength: 128,
      sha256: sha256Of(List<int>.generate(128, (index) => index)),
    );
    balancedArtifact = artifactFixture(
      id: 'whisper-small-q5',
      tier: ModelTier.balanced,
      byteLength: 256,
      sha256: sha256Of(List<int>.generate(256, (index) => index)),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<ModelManifest> manifestWith(List<ModelArtifact> artifacts) async =>
      ModelManifest.parse(manifestJson(artifacts));

  test('lists released profiles for the native engine in tier order', () async {
    final repository = LocalModelRepository(
      manifestLoader: () => manifestWith([fastArtifact, balancedArtifact]),
      storage: storage,
      engine: ModelEngine.nativeFfi,
    );

    final profiles = await repository.listProfiles();

    expect(profiles.map((profile) => profile.tier), [
      ModelTier.fast,
      ModelTier.balanced,
    ]);
    expect(profiles.first.byteLength, 128);
    expect(profiles.last.byteLength, 256);
    expect(profiles.first.quantization, ModelQuantization.q5_1);
  });

  test('reports installed artifacts and resumable partial bytes', () async {
    final repository = LocalModelRepository(
      manifestLoader: () => manifestWith([fastArtifact, balancedArtifact]),
      storage: storage,
      engine: ModelEngine.nativeFfi,
    );
    final model = await storage.modelFile(fastArtifact.id);
    await model.parent.create(recursive: true);
    await model.writeAsBytes(List.filled(fastArtifact.byteLength, 1));
    final part = await storage.partialFile(balancedArtifact.id);
    await part.writeAsBytes(List.filled(10, 1));

    final installed = await repository.installationFor(ModelTier.fast);
    final partial = await repository.installationFor(ModelTier.balanced);

    expect(installed!.installed, isTrue);
    expect(partial!.installed, isFalse);
    expect(partial.partialBytes, 10);
  });

  test('delete removes installed and partial state', () async {
    final repository = LocalModelRepository(
      manifestLoader: () => manifestWith([fastArtifact]),
      storage: storage,
      engine: ModelEngine.nativeFfi,
    );
    final model = await storage.modelFile(fastArtifact.id);
    await model.parent.create(recursive: true);
    await model.writeAsBytes(List.filled(fastArtifact.byteLength, 1));
    final part = await storage.partialFile(fastArtifact.id);
    await part.writeAsBytes(List.filled(4, 1));

    await repository.delete(ModelTier.fast);

    expect(await model.exists(), isFalse);
    expect(await part.exists(), isFalse);
  });

  test('an empty manifest yields no profiles and typed delete failure',
      () async {
    final repository = LocalModelRepository(
      manifestLoader: () => manifestWith(const []),
      storage: storage,
      engine: ModelEngine.nativeFfi,
    );

    expect(await repository.listProfiles(), isEmpty);
    expect(await repository.installationFor(ModelTier.fast), isNull);
    await expectLater(
      repository.delete(ModelTier.fast),
      throwsA(isA<EngineFailure>().having(
        (error) => error.code,
        'code',
        EngineFailureCode.modelUnavailable,
      )),
    );
  });

  test('an invalid manifest becomes a typed modelUnavailable failure',
      () async {
    final repository = LocalModelRepository(
      manifestLoader: () async => throw const FormatException('bad manifest'),
      storage: storage,
      engine: ModelEngine.nativeFfi,
    );

    await expectLater(
      repository.listProfiles(),
      throwsA(isA<EngineFailure>().having(
        (error) => error.code,
        'code',
        EngineFailureCode.modelUnavailable,
      )),
    );
  });

  test('download service verifies, installs and maps progress stages',
      () async {
    final bytes = List<int>.generate(64, (index) => index);
    final artifact = artifactFixture(
      id: 'whisper-base-q5',
      byteLength: bytes.length,
      sha256: sha256Of(bytes),
    );
    final transport = _FakeTransport(bytes);
    final service = LocalModelDownloadService(
      manifestLoader: () => manifestWith([artifact]),
      storage: storage,
      transport: transport,
      engine: ModelEngine.nativeFfi,
    );
    final progress = <ModelDownloadProgress>[];

    await service.download(
      ModelTier.fast,
      cancellation: TestCancellation(),
      onProgress: progress.add,
    );

    expect(transport.requests.single.uri, artifact.source);
    expect(
      progress.map((event) => event.stage),
      contains(ModelDownloadStage.downloading),
    );
    expect(progress.last.stage, ModelDownloadStage.verifying);
    expect(
      await (await storage.modelFile(artifact.id)).readAsBytes(),
      bytes,
    );
    await service.dispose();
  });
}
