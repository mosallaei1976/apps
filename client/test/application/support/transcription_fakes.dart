import 'dart:async';

import 'package:client/features/transcriber/application/transcription_coordinator.dart';
import 'package:client/features/transcriber/domain/engine/abstract_engine_interface.dart';
import 'package:client/features/transcriber/domain/ports/audio_preparation.dart';
import 'package:client/features/transcriber/domain/ports/cancellation_signal.dart';
import 'package:client/features/transcriber/domain/ports/verified_model_access.dart';

import '../../domain/support/controlled_engine.dart';

final class FakeAudioPreparation implements AudioPreparation {
  final List<String> trace;
  final started = Completer<void>();
  final temporaryJobs = <String>{};
  final cleanedJobs = <String>[];
  final protectedResources = <String>{
    'source-media',
    'final-export',
    'verified-model',
    'resumable-download',
  };
  List<PreparedAudio> chunks = [
    PreparedAudio(audioId: 'audio-1', duration: const Duration(seconds: 2)),
  ];
  Future<List<PreparedAudio>> Function(CancellationSignal)? prepareAction;
  Future<void> Function()? cleanupAction;
  CancellationSignal? signal;

  FakeAudioPreparation(this.trace);

  @override
  Future<List<PreparedAudio>> prepare({
    required String sourceId,
    required String jobId,
    required CancellationSignal cancellation,
  }) async {
    trace.add('prepare:$sourceId');
    temporaryJobs.add(jobId);
    signal = cancellation;
    if (!started.isCompleted) started.complete();
    cancellation.throwIfCancelled();
    final result = await prepareAction?.call(cancellation) ?? chunks;
    cancellation.throwIfCancelled();
    return result;
  }

  @override
  Future<void> cleanup(String jobId) async {
    trace.add('cleanup');
    cleanedJobs.add(jobId);
    await cleanupAction?.call();
    temporaryJobs.remove(jobId);
  }
}

final class FakeVerifiedModels implements VerifiedModelAccess {
  final List<String> trace;
  Future<ModelSpec> Function(ModelTier, CancellationSignal)? action;

  FakeVerifiedModels(this.trace);

  @override
  Future<ModelSpec> resolveVerified(ModelTier tier,
      {required CancellationSignal cancellation}) async {
    trace.add('resolve:${tier.name}');
    cancellation.throwIfCancelled();
    final model = await action?.call(tier, cancellation) ??
        ModelSpec(
          id: '${tier.name}-q5',
          tier: tier,
          artifactId: 'verified-${tier.name}',
        );
    cancellation.throwIfCancelled();
    return model;
  }
}

final class EngineStart {
  const EngineStart(this.audio, this.jobId);

  final PreparedAudio audio;
  final String jobId;
}

final class RecordingEngine implements AbstractEngineInterface {
  final List<String> trace;
  final ControlledEngine inner;
  final starts = <EngineStart>[];
  Completer<void> _changed = Completer<void>();
  Future<void> Function()? initializeAction;
  Future<void> Function()? loadAction;
  Stream<TranscriptionEvent> Function(EngineStart)? script;
  int cancelCalls = 0;

  RecordingEngine(this.trace, {Future<void> Function()? cleanup})
      : inner = ControlledEngine(cleanup: cleanup);

  Future<EngineStart> waitForStart(int index) async {
    while (starts.length <= index) {
      await _changed.future;
    }
    return starts[index];
  }

  @override
  EngineStatus get status => inner.status;

  @override
  Stream<EngineStatus> get statusChanges => inner.statusChanges;

  @override
  Stream<ModelLoadProgress> get modelLoadProgress => inner.modelLoadProgress;

  @override
  Future<void> initialize() async {
    trace.add('initialize');
    await initializeAction?.call();
    await inner.initialize();
  }

  @override
  Future<void> loadModel(ModelSpec model) async {
    trace.add('load:${model.tier.name}');
    await loadAction?.call();
    await inner.loadModel(model);
  }

  @override
  Future<void> unloadModel() => inner.unloadModel();

  @override
  Stream<TranscriptionEvent> transcribe(
    PreparedAudio audio, {
    required String jobId,
    required TranscriptionOptions options,
  }) {
    trace.add('transcribe:${audio.audioId}');
    final start = EngineStart(audio, jobId);
    final stream = script?.call(start) ??
        inner.transcribe(audio, jobId: jobId, options: options);
    late StreamSubscription<TranscriptionEvent> subscription;
    late StreamController<TranscriptionEvent> output;
    output = StreamController<TranscriptionEvent>(
      onListen: () {
        subscription = stream.listen(output.add,
            onError: output.addError, onDone: output.close);
        starts.add(start);
        _changed.complete();
        _changed = Completer<void>();
      },
      onPause: () => subscription.pause(),
      onResume: () => subscription.resume(),
      onCancel: () => subscription.cancel(),
    );
    return output.stream;
  }

  @override
  Future<void> cancel(String jobId) {
    trace.add('engine-cancel');
    cancelCalls++;
    return inner.cancel(jobId);
  }

  @override
  Future<void> dispose() => inner.dispose();
}

final class JobProbe {
  final events = <TranscriptionJobEvent>[];
  final errors = <Object>[];
  final done = Completer<void>();
  late final StreamSubscription<TranscriptionJobEvent> subscription;

  JobProbe(Stream<TranscriptionJobEvent> stream) {
    subscription =
        stream.listen(events.add, onError: errors.add, onDone: done.complete);
  }
}

final class TranscriptionHarness {
  final trace = <String>[];
  late final audio = FakeAudioPreparation(trace);
  late final models = FakeVerifiedModels(trace);
  late final engine = RecordingEngine(trace, cleanup: engineCleanup);
  late final coordinator = TranscriptionCoordinator(
      engine: engine, audioPreparation: audio, models: models);
  final Future<void> Function()? engineCleanup;

  TranscriptionHarness({this.engineCleanup});

  JobProbe start({String jobId = 'job-1', ModelTier tier = ModelTier.fast}) =>
      JobProbe(coordinator.transcribe(
          jobId: jobId, sourceId: 'source-media', tier: tier));

  TranscriptSegment segment(
    int chunk, {
    String text = 'سلام',
    String segmentId = 'segment-1',
    bool isFinal = true,
    Duration start = Duration.zero,
    Duration end = const Duration(seconds: 1),
  }) =>
      TranscriptSegment(
          jobId: engine.starts[chunk].jobId,
          segmentId: segmentId,
          text: text,
          start: start,
          end: end,
          isFinal: isFinal,
          confidence: 0.8);

  Future<void> dispose() async {
    await coordinator.dispose();
    await engine.dispose();
  }
}
