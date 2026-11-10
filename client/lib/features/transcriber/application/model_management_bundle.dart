import '../domain/ports/model_management.dart';

/// The model-management adapters injected by the composition root.
final class ModelManagementBundle {
  const ModelManagementBundle({
    required this.repository,
    required this.downloadService,
  });

  final ModelRepository repository;
  final ModelDownloadService downloadService;

  Future<void> dispose() => downloadService.dispose();
}
