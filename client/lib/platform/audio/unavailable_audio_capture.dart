import '../../features/transcriber/domain/engine/engine_failure.dart';
import '../../features/transcriber/domain/ports/audio_capture.dart';

/// Explicitly unavailable capture adapter for platforms/builds without a
/// validated microphone backend. It never fabricates captured audio.
final class UnavailableAudioCapture implements AudioCapture {
  const UnavailableAudioCapture([
    this.reason = 'Microphone capture is not available in this build.',
  ]);

  final String reason;

  @override
  Future<String> start() async {
    throw EngineFailure(EngineFailureCode.unsupported, reason);
  }

  @override
  Future<void> stop(String captureId) async {}

  @override
  Future<void> cancel(String captureId) async {}

  @override
  Future<void> discard(String captureId) async {}

  @override
  Future<void> dispose() async {}
}
