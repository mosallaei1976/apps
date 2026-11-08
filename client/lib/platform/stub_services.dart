import '../features/transcriber/domain/engine/abstract_engine_interface.dart';
import '../features/transcriber/domain/ports/audio_preparation.dart';
import '../features/transcriber/domain/ports/cancellation_signal.dart';
import '../features/transcriber/domain/ports/verified_model_access.dart';

/// Temporary adapters used until audio preparation and model storage exist.
///
/// They fail explicitly instead of fabricating prepared audio or model files.
final class UnavailableAudioPreparation implements AudioPreparation {
  const UnavailableAudioPreparation();

  @override
  Future<List<PreparedAudio>> prepare({
    required String sourceId,
    required String jobId,
    required CancellationSignal cancellation,
  }) async {
    cancellation.throwIfCancelled();
    throw const EngineFailure(
      EngineFailureCode.unsupported,
      'Audio preparation is not implemented in this build.',
    );
  }

  @override
  Future<void> cleanup(String jobId) async {}
}

final class UnavailableVerifiedModelAccess implements VerifiedModelAccess {
  const UnavailableVerifiedModelAccess();

  @override
  Future<ModelSpec> resolveVerified(
    ModelTier tier, {
    required CancellationSignal cancellation,
  }) async {
    cancellation.throwIfCancelled();
    throw const EngineFailure(
      EngineFailureCode.unsupported,
      'Verified model access is not implemented in this build.',
    );
  }
}
