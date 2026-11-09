/// Owns microphone capture for one application session.
///
/// Capture identifiers are opaque domain values. Local file paths, recorder
/// handles and temporary-directory details stay inside the platform adapter.
abstract interface class AudioCapture {
  /// Starts a capture and returns its opaque identifier.
  ///
  /// Implementations must create only application-owned temporary audio under
  /// their managed capture directory. A second capture while one is active is
  /// rejected with `busy`.
  Future<String> start();

  /// Finalizes a capture so its audio can be prepared for inference.
  Future<void> stop(String captureId);

  /// Aborts an active capture and removes its temporary audio.
  Future<void> cancel(String captureId);

  /// Removes a finished capture's temporary audio.
  ///
  /// This is idempotent and safe after [stop].
  Future<void> discard(String captureId);

  /// Releases the recorder and removes any remaining managed capture files.
  Future<void> dispose();
}
