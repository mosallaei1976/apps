import 'dart:async';

import '../domain/engine/abstract_engine_interface.dart';
import '../domain/ports/audio_preparation.dart';
import '../domain/ports/cancellation_signal.dart';
import '../domain/ports/verified_model_access.dart';
import 'transcription_job_event.dart';

export 'transcription_job_event.dart';

final class TranscriptionCoordinator {
  static final _engineJobs = Expando<_JobRun>();
  static int _sequence = 0;

  final AbstractEngineInterface _engine;
  final AudioPreparation _audioPreparation;
  final VerifiedModelAccess _models;
  _JobRun? _active;
  Future<void>? _disposal;

  TranscriptionCoordinator({
    required AbstractEngineInterface engine,
    required AudioPreparation audioPreparation,
    required VerifiedModelAccess models,
  })  : _engine = engine,
        _audioPreparation = audioPreparation,
        _models = models;

  Stream<TranscriptionJobEvent> transcribe({
    required String jobId,
    required String sourceId,
    required ModelTier tier,
    TranscriptionOptions? options,
  }) {
    _JobRun? run;
    late StreamController<TranscriptionJobEvent> output;
    output = StreamController<TranscriptionJobEvent>(
      onListen: () {
        EngineFailure? rejection;
        if (_disposal != null) {
          rejection = const EngineFailure(
            EngineFailureCode.disposed,
            'Coordinator is disposed.',
          );
        } else if (_engineJobs[_engine] != null) {
          rejection = const EngineFailure(
            EngineFailureCode.busy,
            'An engine job is already active.',
          );
        } else if (jobId.trim().isEmpty || sourceId.trim().isEmpty) {
          rejection = const EngineFailure(
            EngineFailureCode.invalidRequest,
            'Job and source IDs are required.',
          );
        }
        if (rejection != null) {
          output.addError(rejection);
          unawaited(output.close());
          return;
        }
        final admitted = _JobRun(jobId, 'job-${_sequence++}', output);
        run = admitted;
        _active = admitted;
        _engineJobs[_engine] = admitted;
        unawaited(_execute(
            admitted, sourceId, tier, options ?? TranscriptionOptions()));
      },
      onPause: () => run?.pause(),
      onResume: () => run?.resume(),
      onCancel: () => run == null || run!.finished
          ? Future<void>.value()
          : _cancelRun(run!),
    );
    return output.stream;
  }

  Future<void> cancel(String jobId) {
    final run = _active;
    if (run == null || run.jobId != jobId || run.finished) {
      return Future<void>.value();
    }
    return _cancelRun(run);
  }

  Future<void> _cancelRun(_JobRun run) {
    run.cancellation.cancel();
    run.resume();
    return run.cancelFuture ??= run.done.future.then((_) {
      if (run.failure != null) throw run.failure!;
    });
  }

  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    final run = _active;
    if (run != null && !run.finished) await _cancelRun(run);
  }

  Future<void> _execute(_JobRun run, String sourceId, ModelTier tier,
      TranscriptionOptions options) async {
    try {
      _stage(run, TranscriptionStage.checkingReadiness);
      switch (_engine.status) {
        case EngineStatus.uninitialized:
        case EngineStatus.failed:
          await _engine.initialize();
        case EngineStatus.initialized:
        case EngineStatus.ready:
          break;
        case EngineStatus.disposed:
          throw const EngineFailure(
              EngineFailureCode.disposed, 'Engine is disposed.');
        default:
          throw const EngineFailure(
              EngineFailureCode.busy, 'Engine is not idle.');
      }
      run.cancellation.throwIfCancelled();
      if (_engine.status != EngineStatus.initialized &&
          _engine.status != EngineStatus.ready) {
        throw const EngineFailure(EngineFailureCode.notReady,
            'Engine initialization did not become ready.');
      }

      _stage(run, TranscriptionStage.resolvingModel);
      final model =
          await _models.resolveVerified(tier, cancellation: run.cancellation);
      run.cancellation.throwIfCancelled();
      if (model.tier != tier) {
        throw const EngineFailure(EngineFailureCode.modelUnavailable,
            'Verified model tier does not match the request.');
      }

      _stage(run, TranscriptionStage.preparingAudio);
      final chunks = List<PreparedAudio>.unmodifiable(
        await _audioPreparation.prepare(
            sourceId: sourceId,
            jobId: run.resourceId,
            cancellation: run.cancellation),
      );
      run.cancellation.throwIfCancelled();
      _validateChunks(chunks);
      if (chunks.isNotEmpty) {
        _stage(run, TranscriptionStage.loadingModel);
        var modelProgressComplete = false;
        final progress = _engine.modelLoadProgress.listen(
          (progress) {
            if (progress.modelId == model.id &&
                !run.output.isPaused &&
                !run.cancellation.isCancelled) {
              run.output.add(JobModelProgress(run.jobId, progress));
              modelProgressComplete = progress.fraction == 1;
            }
          },
          onError: (Object error) {
            run.progressFailure =
                _asFailure(error, EngineFailureCode.modelLoadFailed);
          },
        );
        try {
          await _engine.loadModel(model);
          if (run.progressFailure != null) throw run.progressFailure!;
        } finally {
          await progress.cancel();
        }
        run.cancellation.throwIfCancelled();
        if (_engine.status != EngineStatus.ready) {
          throw const EngineFailure(EngineFailureCode.notReady,
              'Model loading did not make the engine ready.');
        }
        if (!modelProgressComplete) {
          run.output.add(JobModelProgress(
              run.jobId, ModelLoadProgress(modelId: model.id, fraction: 1)));
        }
        _stage(run, TranscriptionStage.transcribing);
        final total = chunks.fold<int>(
            0, (total, chunk) => total + chunk.duration.inMicroseconds);
        var completed = 0;
        for (var index = 0; index < chunks.length; index++) {
          run.cancellation.throwIfCancelled();
          await _transcribeChunk(run, chunks[index], index, chunks.length,
              completed, total, options);
          run.cancellation.throwIfCancelled();
          completed += chunks[index].duration.inMicroseconds;
        }
      }
    } catch (error) {
      if (!(error is EngineFailure &&
          error.code == EngineFailureCode.cancelled &&
          run.cancellation.isCancelled)) {
        run.failure = _asFailure(error, _stageFailure(run.stage));
      }
    } finally {
      _stage(run, TranscriptionStage.cleaningUp);
      try {
        await _audioPreparation.cleanup(run.resourceId);
      } catch (error) {
        final primary = run.failure;
        run.failure = primary == null
            ? _asFailure(error, EngineFailureCode.ioError)
            : EngineFailure(primary.code,
                '${primary.message} Temporary audio cleanup also failed.');
      }
      _engineJobs[_engine] = null;
      _active = null;
      run.finished = true;
      final segments = run.segments.values
          .where((event) => event.segment.isFinal)
          .toList()
        ..sort(
            (first, second) => first.sourceStart.compareTo(second.sourceStart));
      if (run.failure != null) {
        run.output.addError(run.failure!);
      } else if (run.cancellation.isCancelled) {
        run.output.add(JobCancelled(run.jobId, segments));
      } else {
        run.output.add(JobCompleted(run.jobId, segments));
      }
      run.done.complete();
      unawaited(run.output.close());
    }
  }

  Future<void> _transcribeChunk(_JobRun run, PreparedAudio audio, int index,
      int count, int completed, int total, TranscriptionOptions options) async {
    final engineJobId = '${run.resourceId}:$index';
    final iterator = StreamIterator(
        _engine.transcribe(audio, jobId: engineJobId, options: options));
    TranscriptionEvent? terminal;
    var closed = false;
    var finished = false;
    Future<void>? stopping;
    Future<void> stop() => stopping ??= () async {
          try {
            await _engine.cancel(engineJobId);
          } finally {
            await iterator.cancel();
          }
        }();
    unawaited(run.cancellation.whenCancelled.then((_) async {
      if (!finished) {
        try {
          await stop();
        } catch (_) {}
      }
    }));
    try {
      while (true) {
        await run.waitForResume();
        run.cancellation.throwIfCancelled();
        final hasNext = await iterator.moveNext();
        run.cancellation.throwIfCancelled();
        if (!hasNext) {
          closed = true;
          break;
        }
        final event = iterator.current;
        if (terminal != null || event.jobId != engineJobId) {
          throw const EngineFailure(EngineFailureCode.inferenceFailed,
              'Invalid engine event sequence or job ID.');
        }
        switch (event) {
          case TranscriptSegment():
            if (!event.isFinal && !options.emitPartials) break;
            final update = JobSegment(run.jobId,
                segment: event, chunkIndex: index, audio: audio);
            if (run.segments[update.key]?.segment.isFinal ?? false) {
              throw const EngineFailure(EngineFailureCode.inferenceFailed,
                  'A finalized segment was revised.');
            }
            run.segments[update.key] = update;
            run.output.add(update);
          case TranscriptionProgress():
            final fraction = event.fraction;
            run.output.add(JobTranscriptionProgress(run.jobId,
                progress: event,
                chunkIndex: index,
                chunkCount: count,
                overallFraction: fraction == null
                    ? null
                    : (completed + fraction * audio.duration.inMicroseconds) /
                        total));
          case TranscriptionCompleted():
            if (run.segments.values.any((segment) =>
                segment.chunkIndex == index && !segment.segment.isFinal)) {
              throw const EngineFailure(EngineFailureCode.inferenceFailed,
                  'Engine completed with unresolved partial segments.');
            }
            terminal = event;
          case TranscriptionCancelled():
            terminal = event;
            run.cancellation.cancel();
        }
      }
      if (terminal == null) {
        throw const EngineFailure(EngineFailureCode.inferenceFailed,
            'Engine stream closed without a terminal event.');
      }
    } finally {
      try {
        if (!closed || terminal is! TranscriptionCompleted) await stop();
      } finally {
        try {
          await iterator.cancel();
        } finally {
          finished = true;
        }
      }
    }
  }

  void _stage(_JobRun run, TranscriptionStage stage) {
    run.stage = stage;
    run.output.add(JobStageChanged(run.jobId, stage));
  }

  void _validateChunks(List<PreparedAudio> chunks) {
    var previousEnd = Duration.zero;
    final identifiers = <String>{};
    for (final chunk in chunks) {
      if (chunk.sourceOffset < previousEnd || !identifiers.add(chunk.audioId)) {
        throw const EngineFailure(EngineFailureCode.invalidAudio,
            'Prepared chunks must be unique, ordered and non-overlapping.');
      }
      previousEnd = chunk.sourceOffset + chunk.duration;
    }
  }

  EngineFailure _asFailure(Object error, EngineFailureCode fallback) => error
          is EngineFailure
      ? error
      : EngineFailure(
          fallback, 'Transcription job failed during an adapter operation.');

  EngineFailureCode _stageFailure(TranscriptionStage stage) => switch (stage) {
        TranscriptionStage.checkingReadiness =>
          EngineFailureCode.initializationFailed,
        TranscriptionStage.resolvingModel => EngineFailureCode.modelUnavailable,
        TranscriptionStage.preparingAudio => EngineFailureCode.invalidAudio,
        TranscriptionStage.loadingModel => EngineFailureCode.modelLoadFailed,
        TranscriptionStage.transcribing => EngineFailureCode.inferenceFailed,
        TranscriptionStage.cleaningUp => EngineFailureCode.ioError,
      };
}

final class _JobRun {
  final String jobId;
  final String resourceId;
  final StreamController<TranscriptionJobEvent> output;
  final cancellation = _Cancellation();
  final done = Completer<void>();
  final segments = <String, JobSegment>{};
  TranscriptionStage stage = TranscriptionStage.checkingReadiness;
  EngineFailure? failure;
  EngineFailure? progressFailure;
  Future<void>? cancelFuture;
  Completer<void>? _resume;
  bool finished = false;

  _JobRun(this.jobId, this.resourceId, this.output);

  void pause() => _resume ??= Completer<void>();

  void resume() {
    _resume?.complete();
    _resume = null;
  }

  Future<void> waitForResume() async {
    final resume = _resume;
    if (resume != null) {
      await resume.future;
    }
  }
}

final class _Cancellation implements CancellationSignal {
  final _cancelled = Completer<void>();

  @override
  bool get isCancelled => _cancelled.isCompleted;

  @override
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  @override
  void throwIfCancelled() {
    if (isCancelled) {
      throw const EngineFailure(
          EngineFailureCode.cancelled, 'Job was cancelled.');
    }
  }
}
