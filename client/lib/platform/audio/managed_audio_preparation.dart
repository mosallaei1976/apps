import '../../features/transcriber/domain/ports/audio_preparation.dart';

/// Platform lifecycle for the audio-preparation adapter.
///
/// The domain port intentionally exposes only preparation and scoped cleanup.
/// Temporary-job expiry and worker shutdown belong to the composition root.
abstract interface class ManagedAudioPreparation implements AudioPreparation {
  /// Removes job directories whose last activity is older than [maxAge].
  ///
  /// This is best effort and must never remove capture sources, installed
  /// models, transcripts or exports.
  Future<void> sweepStaleJobs({
    Duration maxAge = const Duration(hours: 24),
    DateTime? now,
  });

  /// Releases the preparation worker. Idempotent.
  Future<void> dispose();
}
