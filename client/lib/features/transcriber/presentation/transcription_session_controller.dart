import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/transcription_coordinator.dart';
import '../domain/engine/engine_failure.dart';
import '../domain/engine/engine_types.dart';
import '../domain/ports/audio_capture.dart';

enum TranscriptionPhase {
  idle,
  recording,
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

  bool get isRecording => phase == TranscriptionPhase.recording;

  bool get isProcessing =>
      phase == TranscriptionPhase.active ||
      phase == TranscriptionPhase.cancelling;

  bool get isActive => isRecording || isProcessing;

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
  TranscriptionSessionController(
    this._coordinator,
    this._capture,
  ) : super(const TranscriptionSessionState());

  final TranscriptionCoordinator _coordinator;
  final AudioCapture _capture;
  StreamSubscription<TranscriptionJobEvent>? _subscription;
  String? _jobId;
  String? _captureId;
  Future<void>? _captureStart;
  ModelTier _tier = ModelTier.fast;
  bool _cancelRequested = false;
  int _sequence = 0;

  Future<void> startRecording({ModelTier tier = ModelTier.fast}) async {
    if (state.isActive) return;

    _subscription?.cancel();
    _tier = tier;
    _cancelRequested = false;
    state = const TranscriptionSessionState(
      phase: TranscriptionPhase.recording,
    );
    final pending = _startCapture();
    _captureStart = pending;
    try {
      await pending;
    } finally {
      if (identical(_captureStart, pending)) _captureStart = null;
    }
  }

  Future<void> _startCapture() async {
    try {
      final captureId = await _capture.start();
      if (!mounted) {
        await _capture.cancel(captureId);
        return;
      }
      _captureId = captureId;
    } on EngineFailure catch (error) {
      if (!mounted) return;
      state = TranscriptionSessionState(
        phase: TranscriptionPhase.failed,
        failure: error,
      );
    } on Object {
      if (!mounted) return;
      state = const TranscriptionSessionState(
        phase: TranscriptionPhase.failed,
        failure: EngineFailure(
          EngineFailureCode.unknown,
          'Microphone capture could not start.',
        ),
      );
    }
  }

  /// Stops the microphone and starts a transcription job for that capture.
  Future<void> stopRecording() async {
    if (state.phase != TranscriptionPhase.recording) return;

    final pending = _captureStart;
    if (pending != null) await pending;
    if (!mounted || state.phase != TranscriptionPhase.recording) return;

    final captureId = _captureId;
    if (captureId == null) return;

    state = const TranscriptionSessionState(
      phase: TranscriptionPhase.active,
      stage: TranscriptionStage.checkingReadiness,
    );
    _cancelRequested = false;
    try {
      await _capture.stop(captureId);
    } on Object catch (error) {
      _discardCapture();
      if (!mounted) return;
      state = TranscriptionSessionState(
        phase: TranscriptionPhase.failed,
        segments: state.segments,
        failure: _asFailure(error),
      );
      return;
    }
    if (!mounted) {
      await _capture.discard(captureId);
      _captureId = null;
      return;
    }
    if (_cancelRequested) {
      _cancelRequested = false;
      await _capture.discard(captureId);
      _captureId = null;
      if (!mounted) return;
      state = TranscriptionSessionState(
        phase: TranscriptionPhase.cancelled,
        segments: state.segments,
      );
      return;
    }
    _beginJob(captureId);
  }

  Future<void> cancel() async {
    if (state.phase == TranscriptionPhase.recording) {
      final pending = _captureStart;
      if (pending != null) await pending;
      final captureId = _captureId;
      _captureId = null;
      _cancelRequested = false;
      if (captureId != null) {
        try {
          await _capture.cancel(captureId);
        } on Object {
          // The adapter retains failed deletions for its next cleanup attempt;
          // cancellation itself must still reach a terminal state.
        }
      }
      if (!mounted) return;
      state = TranscriptionSessionState(
        phase: TranscriptionPhase.cancelled,
        segments: state.segments,
      );
      return;
    }

    final jobId = _jobId;
    if (jobId == null) {
      if (state.isProcessing) {
        _cancelRequested = true;
        state = state.copyWith(phase: TranscriptionPhase.cancelling);
      }
      return;
    }
    if (!state.isProcessing) return;

    state = state.copyWith(phase: TranscriptionPhase.cancelling);
    try {
      await _coordinator.cancel(jobId);
    } catch (error) {
      if (!mounted) return;
      _discardCapture();
      state = state.copyWith(
        phase: TranscriptionPhase.failed,
        failure: _asFailure(error),
      );
    }
  }

  void clearTranscript() {
    if (state.isActive) return;
    _cancelRequested = false;
    state = const TranscriptionSessionState();
  }

  void _beginJob(String sourceId) {
    final jobId = 'ui-${_sequence++}';
    _jobId = jobId;
    _subscription = _coordinator
        .transcribe(
          jobId: jobId,
          sourceId: sourceId,
          tier: _tier,
        )
        .listen(_handleEvent, onError: _handleError, onDone: _handleDone);
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
        _cancelRequested = false;
        _discardCapture();
        state = TranscriptionSessionState(
          phase: TranscriptionPhase.completed,
          segments: event.segments,
          modelProgress: state.modelProgress,
          overallProgress: 1,
        );
      case JobCancelled():
        _jobId = null;
        _cancelRequested = false;
        _discardCapture();
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
    _cancelRequested = false;
    _discardCapture();
    state = TranscriptionSessionState(
      phase: TranscriptionPhase.failed,
      segments: state.segments,
      failure: _asFailure(error),
    );
  }

  void _handleDone() {
    if (!mounted || !state.isProcessing) return;
    _jobId = null;
    _cancelRequested = false;
    _discardCapture();
    state = state.copyWith(
      phase: TranscriptionPhase.failed,
      failure: const EngineFailure(
        EngineFailureCode.unknown,
        'The transcription stream ended unexpectedly.',
      ),
    );
  }

  void _discardCapture() {
    final captureId = _captureId;
    _captureId = null;
    if (captureId == null) return;
    unawaited(
      _capture.discard(captureId).then<void>(
        (_) {},
        onError: (Object _) {},
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
    final captureId = _captureId;
    _captureId = null;
    if (captureId != null) {
      unawaited(
        _capture.cancel(captureId).then<void>(
          (_) {},
          onError: (Object _) {},
        ),
      );
    }
    super.dispose();
  }
}
