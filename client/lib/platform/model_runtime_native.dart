import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../features/transcriber/domain/ports/verified_model_access.dart';
import 'models/local_verified_model_access.dart';
import 'models/model_manifest.dart';
import 'models/model_storage.dart';

/// Native builds verify installed artifacts against the bundled trusted
/// manifest. The manifest intentionally stays empty until an artifact is
/// pinned, licensed, measured and tested against the selected engine build.
VerifiedModelAccess createVerifiedModelAccess() {
  return LocalVerifiedModelAccess(
    manifestLoader: () async => ModelManifest.parse(
      await rootBundle.loadString('assets/models/manifest.json'),
    ),
    storage: ModelStorage(rootDirectory: getApplicationSupportDirectory),
    engine: ModelEngine.nativeFfi,
  );
}
