import '../features/transcriber/application/model_management_bundle.dart';
import 'models/unavailable_model_management.dart';

/// Browser model storage and downloads are not implemented or validated.
ModelManagementBundle createModelManagementBundle() =>
    const ModelManagementBundle(
      repository: UnavailableModelRepository(),
      downloadService: UnavailableModelDownloadService(),
    );
