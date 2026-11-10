import '../../features/transcriber/domain/engine/engine_failure.dart';
import '../../features/transcriber/domain/engine/engine_types.dart';
import '../../features/transcriber/domain/ports/cancellation_signal.dart';
import '../../features/transcriber/domain/ports/model_management.dart';

const _unavailableReason =
    'Model downloads are not available in this build.';

/// Explicit browser fallback: no local model storage or download transport.
final class UnavailableModelRepository implements ModelRepository {
  const UnavailableModelRepository();

  @override
  Future<List<ModelProfile>> listProfiles() async =>
      throw const EngineFailure(
        EngineFailureCode.unsupported,
        _unavailableReason,
      );

  @override
  Future<ModelInstallation?> installationFor(ModelTier tier) async =>
      throw const EngineFailure(
        EngineFailureCode.unsupported,
        _unavailableReason,
      );

  @override
  Future<void> delete(ModelTier tier) async => throw const EngineFailure(
        EngineFailureCode.unsupported,
        _unavailableReason,
      );
}

final class UnavailableModelDownloadService implements ModelDownloadService {
  const UnavailableModelDownloadService();

  @override
  Future<void> download(
    ModelTier tier, {
    required CancellationSignal cancellation,
    void Function(ModelDownloadProgress progress)? onProgress,
  }) async {
    cancellation.throwIfCancelled();
    throw const EngineFailure(
      EngineFailureCode.unsupported,
      _unavailableReason,
    );
  }

  @override
  Future<void> dispose() async {}
}
