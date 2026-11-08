import '../domain/engine/engine_types.dart';

enum TranscriptionStage {
  checkingReadiness,
  resolvingModel,
  preparingAudio,
  loadingModel,
  transcribing,
  cleaningUp,
}

sealed class TranscriptionJobEvent {
  const TranscriptionJobEvent(this.jobId);

  final String jobId;
}

final class JobStageChanged extends TranscriptionJobEvent {
  const JobStageChanged(super.jobId, this.stage);

  final TranscriptionStage stage;
}

final class JobModelProgress extends TranscriptionJobEvent {
  const JobModelProgress(super.jobId, this.progress);

  final ModelLoadProgress progress;
}

final class JobTranscriptionProgress extends TranscriptionJobEvent {
  const JobTranscriptionProgress(
    super.jobId, {
    required this.progress,
    required this.chunkIndex,
    required this.chunkCount,
    required this.overallFraction,
  });

  final TranscriptionProgress progress;
  final int chunkIndex;
  final int chunkCount;
  final double? overallFraction;
}

final class JobSegment extends TranscriptionJobEvent {
  JobSegment(
    super.jobId, {
    required this.segment,
    required this.chunkIndex,
    required PreparedAudio audio,
  })  : sourceStart = segment.sourceStart(audio),
        sourceEnd = segment.sourceEnd(audio);

  final TranscriptSegment segment;
  final int chunkIndex;
  final Duration sourceStart;
  final Duration sourceEnd;

  String get key => '$chunkIndex:${segment.segmentId}';
}

final class JobCompleted extends TranscriptionJobEvent {
  JobCompleted(super.jobId, Iterable<JobSegment> segments)
      : segments = List.unmodifiable(segments);

  final List<JobSegment> segments;
}

final class JobCancelled extends TranscriptionJobEvent {
  JobCancelled(super.jobId, Iterable<JobSegment> segments)
      : segments = List.unmodifiable(segments);

  final List<JobSegment> segments;
}
