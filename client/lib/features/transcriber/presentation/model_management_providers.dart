import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/model_management_bundle.dart';
import '../application/model_management_controller.dart';
import '../application/model_management_state.dart';
import '../domain/ports/model_management.dart';

/// Injected by the composition root so presentation never constructs a
/// manifest reader, storage directory or HTTP transport.
final modelManagementBundleProvider = Provider<ModelManagementBundle>(
  (ref) => throw UnimplementedError(
    'modelManagementBundleProvider must be overridden at the composition root.',
  ),
);

final modelRepositoryProvider = Provider<ModelRepository>(
  (ref) => ref.watch(modelManagementBundleProvider).repository,
);

final modelDownloadServiceProvider = Provider<ModelDownloadService>(
  (ref) => ref.watch(modelManagementBundleProvider).downloadService,
);

final modelManagementProvider = StateNotifierProvider<
    ModelManagementController, ModelManagementState>((ref) {
  return ModelManagementController(
    repository: ref.watch(modelRepositoryProvider),
    downloadService: ref.watch(modelDownloadServiceProvider),
  );
});
