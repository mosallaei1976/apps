import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/transcription_coordinator.dart';
import '../domain/engine/engine_failure.dart';
import '../domain/engine/engine_types.dart';

enum TranscriptionPhase {
  idle,
  active,
  cancelling,
  completed,
  cancelled,
  failed,
}

final class TranscriptionSessionState {
  const TranscriptionSessionState({
    this.phase = TranscriptionPhase.idle,
    this.stage,
    this.segments = const [],
    this.modelProgress,
    this.overallProgress,
    this.failure,
  });

  final TranscriptionPhase phase;
  final TranscriptionStage? stage;
  final List<JobSegment> segments;
  final double? modelProgress;
  final double? overallProgress;
  final EngineFailure? failure;

  bool get isActive =>
      phase == TranscriptionPhase.active ||
      phase == TranscriptionPhase.cancelling;

  bool get showsStatus =>
      isActive ||
      failure != null ||
      phase == TranscriptionPhase.completed ||
      phase == TranscriptionPhase.cancelled;

  double? get progress => switch (stage) {
        TranscriptionStage.loadingModel => modelProgress,
        TranscriptionStage.transcribing => overallProgress,
        _ => null,
      };

  String get transcriptText => segments
      .map((segment) => segment.segment.text.trim())
      .where((text) => text.isNotEmpty)
      .join(' ');

  TranscriptionSessionState copyWith({
    TranscriptionPhase? phase,
    TranscriptionStage? stage,
    List<JobSegment>? segments,
    double? modelProgress,
    double? overallProgress,
    EngineFailure? failure,
  }) {
    return TranscriptionSessionState(
      phase: phase ?? this.phase,
      stage: stage ?? this.stage,
      segments: segments ?? this.segments,
      modelProgress: modelProgress ?? this.modelProgress,
      overallProgress: overallProgress ?? this.overallProgress,
      failure: failure ?? this.failure,
    );
  }
}

final class TranscriptionSessionController
    extends StateNotifier<TranscriptionSessionState> {
  TranscriptionSessionController(this._coordinator)
      : super(const TranscriptionSessionState());

  final TranscriptionCoordinator _coordinator;
  StreamSubscription<TranscriptionJobEvent>? _subscription;
  String? _jobId;
  int _sequence = 0;

  void start({
    required String sourceId,
    ModelTier tier = ModelTier.fast,
  }) {
    if (state.isActive) return;

    _subscription?.cancel();
    final jobId = 'ui-${_sequence++}';
    _jobId = jobId;
    state = const TranscriptionSessionState(
      phase: TranscriptionPhase.active,
      stage: TranscriptionStage.checkingReadiness,
    );
    _subscription = _coordinator
        .transcribe(
          jobId: jobId,
          sourceId: sourceId,
          tier: tier,
        )
        .listen(_handleEvent, onError: _handleError, onDone: _handleDone);
  }

  Future<void> cancel() async {
    final jobId = _jobId;
    if (jobId == null || !state.isActive) return;

    state = state.copyWith(phase: TranscriptionPhase.cancelling);
    try {
      await _coordinator.cancel(jobId);
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        phase: TranscriptionPhase.failed,
        failure: _asFailure(error),
      );
    }
  }

  void clearTranscript() {
    if (state.isActive) return;
    state = const TranscriptionSessionState();
  }

  void _handleEvent(TranscriptionJobEvent event) {
    if (!mounted || event.jobId != _jobId) return;

    switch (event) {
      case JobStageChanged():
        state = state.copyWith(
          phase: state.phase == TranscriptionPhase.cancelling
              ? TranscriptionPhase.cancelling
              : TranscriptionPhase.active,
          stage: event.stage,
        );
      case JobModelProgress():
        state = TranscriptionSessionState(
          phase: state.phase,
          stage: state.stage,
          segments: state.segments,
          modelProgress: event.progress.fraction,
          overallProgress: state.overallProgress,
          failure: state.failure,
        );
      case JobTranscriptionProgress():
        state = TranscriptionSessionState(
          phase: state.phase,
          stage: state.stage,
          segments: state.segments,
          modelProgress: state.modelProgress,
          overallProgress: event.overallFraction,
          failure: state.failure,
        );
      case JobSegment():
        state = state.copyWith(segments: _upsertSegment(event));
      case JobCompleted():
        _jobId = null;
        state = TranscriptionSessionState(
          phase: TranscriptionPhase.completed,
          segments: event.segments,
          modelProgress: state.modelProgress,
          overallProgress: 1,
        );
      case JobCancelled():
        _jobId = null;
        state = TranscriptionSessionState(
          phase: TranscriptionPhase.cancelled,
          segments: event.segments,
          modelProgress: state.modelProgress,
          overallProgress: state.overallProgress,
        );
    }
  }

  List<JobSegment> _upsertSegment(JobSegment update) {
    final segments = [...state.segments];
    final index = segments.indexWhere((segment) => segment.key == update.key);
    if (index == -1) {
      segments.add(update);
    } else {
      segments[index] = update;
    }
    segments.sort(
      (first, second) => first.sourceStart.compareTo(second.sourceStart),
    );
    return List.unmodifiable(segments);
  }

  void _handleError(Object error) {
    if (!mounted) return;
    _jobId = null;
    state = TranscriptionSessionState(
      phase: TranscriptionPhase.failed,
      segments: state.segments,
      failure: _asFailure(error),
    );
  }

  void _handleDone() {
    if (!mounted || !state.isActive) return;
    _jobId = null;
    state = state.copyWith(
      phase: TranscriptionPhase.failed,
      failure: const EngineFailure(
        EngineFailureCode.unknown,
        'The transcription stream ended unexpectedly.',
      ),
    );
  }

  EngineFailure _asFailure(Object error) => error is EngineFailure
      ? error
      : const EngineFailure(
          EngineFailureCode.unknown,
          'The transcription job failed.',
        );

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
