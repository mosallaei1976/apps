/// One prepared-audio inference request.
final class WhisperInferenceRequest {
  const WhisperInferenceRequest({
    required this.requestId,
    required this.audioPath,
    required this.audioDuration,
    required this.languageCode,
    required this.emitPartials,
  });

  final String requestId;
  final String audioPath;
  final Duration audioDuration;
  final String languageCode;
  final bool emitPartials;
}

/// One final segment produced by the native decoder.
final class WhisperInferenceSegment {
  const WhisperInferenceSegment({
    required this.segmentId,
    required this.text,
    required this.start,
    required this.end,
  });

  final String segmentId;
  final String text;
  final Duration start;
  final Duration end;
}

sealed class WhisperInferenceEvent {
  const WhisperInferenceEvent();
}

final class WhisperInferenceProgress extends WhisperInferenceEvent {
  const WhisperInferenceProgress(this.fraction);

  final double fraction;
}

final class WhisperInferenceSegments extends WhisperInferenceEvent {
  const WhisperInferenceSegments(this.segments);

  final List<WhisperInferenceSegment> segments;
}

final class WhisperInferenceCompleted extends WhisperInferenceEvent {
  const WhisperInferenceCompleted();
}

final class WhisperInferenceCancelled extends WhisperInferenceEvent {
  const WhisperInferenceCancelled();
}

/// Runs whisper.cpp inference outside the UI isolate.
///
/// Implementations own model loading and native resources. The engine maps the
/// emitted events to domain events and is responsible for admission/state.
abstract interface class WhisperInferenceRunner {
  Future<void> initialize({
    required String libraryPath,
    required String expectedSha256,
  });

  Future<void> loadModel({required String modelPath});

  Stream<WhisperInferenceEvent> transcribe(WhisperInferenceRequest request);

  Future<void> cancel(String requestId);

  Future<void> unloadModel();

  Future<void> dispose();
}
