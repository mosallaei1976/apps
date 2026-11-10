import 'dart:io';

import 'package:client/features/transcriber/application/model_management_controller.dart';
import 'package:client/features/transcriber/application/model_management_state.dart';
import 'package:client/features/transcriber/domain/engine/engine_types.dart';
import 'package:client/platform/models/local_model_management.dart';
import 'package:client/platform/models/model_manifest.dart';
import 'package:client/platform/models/model_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_model_management.dart';

void main() {
  late Directory root;
  late ModelStorage storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pt-manifest-controller-');
    storage = ModelStorage(rootDirectory: () async => root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<ModelManifest> loadBundledManifest() async => ModelManifest.parse(
        await File('assets/models/manifest.json').readAsString(),
      );

  test('resolves the real bundled Fast and Balanced profiles', () async {
    final service = FakeModelDownloadService();
    final controller = ModelManagementController(
      repository: LocalModelRepository(
        manifestLoader: loadBundledManifest,
        storage: storage,
        engine: ModelEngine.nativeFfi,
      ),
      downloadService: service,
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.state.isSupported, isTrue);
    expect(controller.state.failure, isNull);
    expect(
      controller.state.profiles.map((entry) => entry.profile.tier),
      [ModelTier.fast, ModelTier.balanced],
    );

    final fast = controller.state.profileFor(ModelTier.fast)!;
    expect(fast.profile.byteLength, 81768585);
    expect(fast.profile.quantization, ModelQuantization.q8_0);
    expect(fast.status, isA<ModelNotDownloaded>());

    final balanced = controller.state.profileFor(ModelTier.balanced)!;
    expect(balanced.profile.byteLength, 190085487);
    expect(balanced.profile.quantization, ModelQuantization.q5_1);
    expect(balanced.status, isA<ModelNotDownloaded>());

    expect(service.calls, isEmpty,
        reason: 'initialization must never start a download');
  });

  test('maps a resumable partial artifact to paused state', () async {
    final manifest = await loadBundledManifest();
    final balanced =
        manifest.artifactFor(ModelTier.balanced, ModelEngine.nativeFfi)!;
    final part = await storage.partialFile(balanced.id);
    await part.writeAsBytes(List.filled(4096, 7), flush: true);

    final controller = ModelManagementController(
      repository: LocalModelRepository(
        manifestLoader: loadBundledManifest,
        storage: storage,
        engine: ModelEngine.nativeFfi,
      ),
      downloadService: FakeModelDownloadService(),
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    final status = controller.state.profileFor(ModelTier.balanced)!.status;
    expect(status, isA<ModelDownloadPaused>());
    expect((status as ModelDownloadPaused).receivedBytes, 4096);
    expect(status.totalBytes, balanced.byteLength);
  });
}
