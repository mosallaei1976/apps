enum EngineStatus {
  uninitialized,
  initialized,
  loadingModel,
  ready,
  transcribing,
  cancelling,
  failed,
  disposed,
}

enum ModelTier { fast, balanced }

enum ModelQuantization { int8, q5K }

final class ModelSpec {
  ModelSpec({
    required String id,
    required this.tier,
    required String artifactId,
    this.quantization = ModelQuantization.q5K,
  })  : id = _requireId(id, 'id'),
        artifactId = _requireId(artifactId, 'artifactId');

  final String id;
  final ModelTier tier;

  final String artifactId;
  final ModelQuantization quantization;

  int get approximateDownloadBytes => switch (tier) {
        ModelTier.fast => 80000000,
        ModelTier.balanced => 200000000,
      };
}

final class ModelLoadProgress {
  ModelLoadProgress({required String modelId, double? fraction})
      : modelId = _requireId(modelId, 'modelId'),
        fraction = _requireFraction(fraction, 'fraction');

  final String modelId;
  final double? fraction;
}

final class PreparedAudio {
  PreparedAudio({
    required String audioId,
    required this.duration,
    this.sourceOffset = Duration.zero,
  }) : audioId = _requireId(audioId, 'audioId') {
    if (duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration', 'Must be positive');
    }
    if (sourceOffset.isNegative) {
      throw ArgumentError.value(
          sourceOffset, 'sourceOffset', 'Must be >= zero');
    }
  }

  final String audioId;
  final Duration duration;

  final Duration sourceOffset;
}

final class TranscriptionOptions {
  TranscriptionOptions({
    String languageCode = 'fa',
    this.emitPartials = true,
  }) : languageCode = _requireId(languageCode, 'languageCode');

  final String languageCode;
  final bool emitPartials;
}

sealed class TranscriptionEvent {
  TranscriptionEvent(String jobId) : jobId = _requireId(jobId, 'jobId');
  final String jobId;
}

final class TranscriptSegment extends TranscriptionEvent {
  TranscriptSegment({
    required String jobId,
    required String segmentId,
    required this.text,
    required this.start,
    required this.end,
    required this.isFinal,
    double? confidence,
  })  : segmentId = _requireId(segmentId, 'segmentId'),
        confidence = _requireFraction(confidence, 'confidence'),
        super(jobId) {
    if (start.isNegative || end < start) {
      throw ArgumentError('Timestamps must satisfy 0 <= start <= end');
    }
  }

  final String segmentId;
  final String text;

  final Duration start;
  final Duration end;

  final bool isFinal;
  final double? confidence;

  Duration sourceStart(PreparedAudio audio) {
    _validateAudioBounds(audio);
    return audio.sourceOffset + start;
  }

  Duration sourceEnd(PreparedAudio audio) {
    _validateAudioBounds(audio);
    return audio.sourceOffset + end;
  }

  void _validateAudioBounds(PreparedAudio audio) {
    if (end > audio.duration) {
      throw ArgumentError('Segment extends beyond prepared audio duration');
    }
  }
}

final class TranscriptionProgress extends TranscriptionEvent {
  TranscriptionProgress({
    required String jobId,
    double? fraction,
  })  : fraction = _requireFraction(fraction, 'fraction'),
        super(jobId);

  final double? fraction;
}

final class TranscriptionCompleted extends TranscriptionEvent {
  TranscriptionCompleted(super.jobId);
}

final class TranscriptionCancelled extends TranscriptionEvent {
  TranscriptionCancelled(super.jobId);
}

String _requireId(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty');
  }
  return value;
}

double? _requireFraction(double? value, String name) {
  if (value != null && (!value.isFinite || value < 0 || value > 1)) {
    throw RangeError.value(value, name, 'Must be null or finite and in [0, 1]');
  }
  return value;
}
