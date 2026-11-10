import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../features/transcriber/application/model_management_bundle.dart';
import 'models/dart_model_download_transport.dart';
import 'models/local_model_management.dart';
import 'models/model_manifest.dart';
import 'models/model_storage.dart';

/// Native composition of manifest-backed model management.
///
/// Downloads remain strictly user-triggered; this factory only wires adapters.
ModelManagementBundle createModelManagementBundle() {
  final storage = ModelStorage(rootDirectory: getApplicationSupportDirectory);
  Future<ModelManifest> loadManifest() async => ModelManifest.parse(
        await rootBundle.loadString('assets/models/manifest.json'),
      );
  return ModelManagementBundle(
    repository: LocalModelRepository(
      manifestLoader: loadManifest,
      storage: storage,
      engine: ModelEngine.nativeFfi,
    ),
    downloadService: LocalModelDownloadService(
      manifestLoader: loadManifest,
      storage: storage,
      transport: DartModelDownloadTransport(),
      engine: ModelEngine.nativeFfi,
    ),
  );
}
