import 'dart:async';

import 'package:client/features/transcriber/domain/engine/abstract_engine_interface.dart';

final class ControlledEngine implements AbstractEngineInterface {
  final Future<void> Function()? cleanup;
  final _statuses = StreamController<EngineStatus>.broadcast();
  final _progress = StreamController<ModelLoadProgress>.broadcast();
  final _pendingSegments = <String>{};
  final _finalSegments = <String>{};
  EngineStatus _status = EngineStatus.uninitialized;
  StreamController<TranscriptionEvent>? _job;
  String? _jobId;
  PreparedAudio? _audio;
  TranscriptionOptions? _options;
  Future<void>? _cancellation;
  Future<void>? _disposal;

  ControlledEngine({this.cleanup});

  @override
  EngineStatus get status => _status;

  @override
  Stream<EngineStatus> get statusChanges => _statuses.stream;

  @override
  Stream<ModelLoadProgress> get modelLoadProgress => _progress.stream;

  @override
  Future<void> initialize() async {
    _ensureAvailable();
    if (_status == EngineStatus.uninitialized) {
      _setStatus(EngineStatus.initialized);
    }
  }

  @override
  Future<void> loadModel(ModelSpec model) async {
    _ensureAvailable();
    if (_status == EngineStatus.uninitialized) {
      throw const EngineFailure(
          EngineFailureCode.notReady, 'Initialize first.');
    }
    _setStatus(EngineStatus.loadingModel);
    _progress.add(ModelLoadProgress(modelId: model.id, fraction: 0));
    _progress.add(ModelLoadProgress(modelId: model.id, fraction: 1));
    _setStatus(EngineStatus.ready);
  }

  @override
  Future<void> unloadModel() async {
    _ensureAvailable();
    if (_status == EngineStatus.ready) {
      _setStatus(EngineStatus.initialized);
    }
  }

  @override
  Stream<TranscriptionEvent> transcribe(
    PreparedAudio audio, {
    required String jobId,
    required TranscriptionOptions options,
  }) {
    late StreamController<TranscriptionEvent> controller;
    controller = StreamController<TranscriptionEvent>(
      onListen: () {
        try {
          _ensureAvailable();
          if (jobId.trim().isEmpty) {
            throw const EngineFailure(
              EngineFailureCode.invalidRequest,
              'Empty job ID.',
            );
          }
          if (_status != EngineStatus.ready) {
            throw const EngineFailure(
                EngineFailureCode.notReady, 'Load first.');
          }
          _job = controller;
          _jobId = jobId;
          _audio = audio;
          _options = options;
          _pendingSegments.clear();
          _finalSegments.clear();
          _setStatus(EngineStatus.transcribing);
        } on EngineFailure catch (failure) {
          controller.addError(failure);
          unawaited(controller.close());
        }
      },
      onCancel: () => identical(_job, controller) ? cancel(jobId) : null,
    );
    return controller.stream;
  }

  void emitSegment(TranscriptSegment segment) {
    if (segment.jobId != _jobId || _finalSegments.contains(segment.segmentId)) {
      throw StateError('Wrong job or already finalized segment');
    }
    segment.sourceEnd(_audio!);
    if (segment.isFinal) {
      _pendingSegments.remove(segment.segmentId);
      _finalSegments.add(segment.segmentId);
    } else {
      if (!_options!.emitPartials) return;
      _pendingSegments.add(segment.segmentId);
    }
    _job!.add(segment);
  }

  void complete() {
    if (_pendingSegments.isNotEmpty) {
      throw StateError('Unresolved partial segments');
    }
    _finish(TranscriptionCompleted(_jobId!));
  }

  void emitProgress(double? fraction) {
    _job!.add(TranscriptionProgress(jobId: _jobId!, fraction: fraction));
  }

  void fail(EngineFailure failure) {
    _job!.addError(failure);
    _releaseJob();
  }

  @override
  Future<void> cancel(String jobId) {
    if (_job == null || _jobId != jobId) return Future<void>.value();
    return _cancellation ??= _cancelJob(jobId);
  }

  Future<void> _cancelJob(String jobId) async {
    _setStatus(EngineStatus.cancelling);
    await cleanup?.call();
    _finish(TranscriptionCancelled(jobId));
    _cancellation = null;
  }

  void _finish(TranscriptionEvent event) {
    _job!.add(event);
    _releaseJob();
  }

  void _releaseJob() {
    final controller = _job!;
    _job = null;
    _jobId = null;
    _audio = null;
    _options = null;
    if (_disposal == null) _setStatus(EngineStatus.ready);
    unawaited(controller.close());
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    if (_jobId != null) await cancel(_jobId!);
    _setStatus(EngineStatus.disposed);
    await Future.wait([_statuses.close(), _progress.close()]);
  }

  void _ensureAvailable() {
    if (_disposal != null || _status == EngineStatus.disposed) {
      throw const EngineFailure(EngineFailureCode.disposed, 'Disposed.');
    }
    if (_job != null) {
      throw const EngineFailure(EngineFailureCode.busy, 'Job active.');
    }
  }

  void _setStatus(EngineStatus status) {
    if (_status != status) {
      _status = status;
      _statuses.add(status);
    }
  }
}
