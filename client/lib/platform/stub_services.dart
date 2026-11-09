import '../features/transcriber/domain/engine/abstract_engine_interface.dart';
import '../features/transcriber/domain/ports/cancellation_signal.dart';
import '../features/transcriber/domain/ports/verified_model_access.dart';
import 'audio/managed_audio_preparation.dart';

/// Explicit adapters for builds or platforms without a validated backend.
///
/// They fail with a typed local error instead of fabricating prepared audio or
/// model files.
final class UnavailableAudioPreparation implements ManagedAudioPreparation {
  const UnavailableAudioPreparation([
    this.reason = 'Audio preparation is not available in this build.',
  ]);

  final String reason;

  @override
  Future<List<PreparedAudio>> prepare({
    required String sourceId,
    required String jobId,
    required CancellationSignal cancellation,
  }) async {
    cancellation.throwIfCancelled();
    throw EngineFailure(EngineFailureCode.unsupported, reason);
  }

  @override
  Future<void> cleanup(String jobId) async {}

  @override
  Future<void> sweepStaleJobs({
    Duration maxAge = const Duration(hours: 24),
    DateTime? now,
  }) async {}

  @override
  Future<void> dispose() async {}
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
