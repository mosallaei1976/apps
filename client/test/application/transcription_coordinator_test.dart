import 'dart:async';

import 'package:client/features/transcriber/application/transcription_coordinator.dart';
import 'package:client/features/transcriber/domain/engine/abstract_engine_interface.dart';
import 'package:client/platform/engine_factory.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/transcription_fakes.dart';

void expectFailure(JobProbe probe, EngineFailureCode code) {
  expect(probe.errors,
      [isA<EngineFailure>().having((error) => error.code, 'code', code)]);
  expect(probe.events.whereType<JobCompleted>(), isEmpty);
  expect(probe.events.whereType<JobCancelled>(), isEmpty);
}

void expectCleaned(TranscriptionHarness harness, {int count = 1}) {
  expect(harness.audio.cleanedJobs, hasLength(count));
  expect(harness.audio.temporaryJobs, isEmpty);
  expect(harness.audio.protectedResources, {
    'source-media',
    'final-export',
    'verified-model',
    'resumable-download',
  });
}

void main() {
  late TranscriptionHarness harness;
  setUp(() => harness = TranscriptionHarness());
  tearDown(() => harness.dispose());

  test(
      'success orders readiness, verification, preparation, model loading and cleanup',
      () async {
    final probe = harness.start(tier: ModelTier.balanced);
    await harness.engine.waitForStart(0);
    harness.engine.inner.emitProgress(0.5);
    harness.engine.inner.emitSegment(harness.segment(0));
    harness.engine.inner.complete();
    await probe.done.future;

    expect(probe.errors, isEmpty);
    expect(harness.trace, [
      'initialize',
      'resolve:balanced',
      'prepare:source-media',
      'load:balanced',
      'transcribe:audio-1',
      'cleanup',
    ]);
    expect(
        probe.events.whereType<JobStageChanged>().map((event) => event.stage),
        TranscriptionStage.values);
    expect(
        probe.events
            .whereType<JobModelProgress>()
            .map((event) => event.progress.fraction),
        [0, 1]);
    expect(
        probe.events
            .whereType<JobTranscriptionProgress>()
            .single
            .overallFraction,
        0.5);
    expect(probe.events.last, isA<JobCompleted>());
    final completed = probe.events.last as JobCompleted;
    expect(completed.segments.single.segment.text, 'سلام');
    expect(() => completed.segments.clear(), throwsUnsupportedError);
    expectCleaned(harness);
  });

  test('partial revisions replace the same keyed segment and final commits it',
      () async {
    final probe = harness.start();
    await harness.engine.waitForStart(0);
    harness.engine.inner
        .emitSegment(harness.segment(0, text: 'س', isFinal: false));
    harness.engine.inner
        .emitSegment(harness.segment(0, text: 'سلا', isFinal: false));
    harness.engine.inner.emitSegment(harness.segment(0));
    harness.engine.inner.complete();
    await probe.done.future;

    final updates = probe.events.whereType<JobSegment>().toList();
    expect(updates.map((event) => event.key).toSet(), hasLength(1));
    expect(updates.map((event) => event.segment.text), ['س', 'سلا', 'سلام']);
    final completed = probe.events.last as JobCompleted;
    expect(completed.segments, hasLength(1));
    expect(completed.segments.single.segment.isFinal, isTrue);
    expectCleaned(harness);
  });

  test(
      'VAD chunks preserve original gaps, unique segment keys and weighted progress',
      () async {
    harness.audio.chunks = [
      PreparedAudio(
          audioId: 'first',
          duration: const Duration(seconds: 2),
          sourceOffset: const Duration(seconds: 5)),
      PreparedAudio(
          audioId: 'second',
          duration: const Duration(seconds: 3),
          sourceOffset: const Duration(seconds: 20)),
    ];
    final probe = harness.start();
    await harness.engine.waitForStart(0);
    harness.engine.inner.emitProgress(0.5);
    harness.engine.inner.emitSegment(harness.segment(0,
        start: const Duration(milliseconds: 500),
        end: const Duration(milliseconds: 1500)));
    harness.engine.inner.complete();
    await harness.engine.waitForStart(1);
    harness.engine.inner.emitProgress(0.5);
    harness.engine.inner.emitSegment(harness.segment(1,
        start: const Duration(seconds: 1), end: const Duration(seconds: 2)));
    harness.engine.inner.complete();
    await probe.done.future;

    final segments = (probe.events.last as JobCompleted).segments;
    expect(segments.map((event) => event.sourceStart), [
      const Duration(milliseconds: 5500),
      const Duration(seconds: 21),
    ]);
    expect(segments.map((event) => event.sourceEnd), [
      const Duration(milliseconds: 6500),
      const Duration(seconds: 22),
    ]);
    expect(segments.map((event) => event.key).toSet(), hasLength(2));
    expect(segments.first.segment.start, const Duration(milliseconds: 500));
    expect(segments.first.segment.confidence, 0.8);
    expect(harness.engine.starts.map((start) => start.jobId).toSet(),
        hasLength(2));
    expect(
        probe.events
            .whereType<JobTranscriptionProgress>()
            .map((event) => event.overallFraction),
        [0.2, 0.7]);
    expectCleaned(harness);
  });

  test('no speech completes without loading a model or invoking inference',
      () async {
    harness.audio.chunks = [];
    final probe = harness.start();
    await probe.done.future;
    expect((probe.events.last as JobCompleted).segments, isEmpty);
    expect(harness.engine.starts, isEmpty);
    expect(harness.trace.where((entry) => entry.startsWith('load:')), isEmpty);
    expectCleaned(harness);
  });

  for (final stage in [
    'verification',
    'preparation',
    'model loading',
    'inference'
  ]) {
    test('$stage failure is typed and cleans temporary resources', () async {
      final code = switch (stage) {
        'verification' => EngineFailureCode.modelUnavailable,
        'preparation' => EngineFailureCode.ioError,
        'model loading' => EngineFailureCode.modelLoadFailed,
        _ => EngineFailureCode.inferenceFailed,
      };
      final error = EngineFailure(code, '$stage failed');
      switch (stage) {
        case 'verification':
          harness.models.action = (_, __) async => throw error;
        case 'preparation':
          harness.audio.prepareAction = (_) async => throw error;
        case 'model loading':
          harness.engine.loadAction = () async => throw error;
      }
      final probe = harness.start();
      if (stage == 'inference') {
        await harness.engine.waitForStart(0);
        harness.engine.inner.fail(error);
      }
      await probe.done.future;
      expectFailure(probe, code);
      expect(
          probe.events
              .whereType<JobModelProgress>()
              .where((event) => event.progress.fraction == 1),
          stage == 'inference' ? hasLength(1) : isEmpty);
      expectCleaned(harness);
      if (stage == 'verification') {
        expect(harness.trace.where((entry) => entry.startsWith('prepare:')),
            isEmpty);
      }
    });
  }

  test('raw adapter exceptions are normalized without leaking platform details',
      () async {
    harness.audio.prepareAction =
        (_) async => throw StateError('private-native-path');
    final probe = harness.start();
    await probe.done.future;
    expectFailure(probe, EngineFailureCode.invalidAudio);
    expect(
        probe.errors.single.toString(), isNot(contains('private-native-path')));
    expectCleaned(harness);
  });

  test('wrong model tier never reaches preparation or engine loading',
      () async {
    harness.models.action = (_, __) async => ModelSpec(
        id: 'wrong', tier: ModelTier.balanced, artifactId: 'verified-wrong');
    final probe = harness.start();
    await probe.done.future;
    expectFailure(probe, EngineFailureCode.modelUnavailable);
    expect(harness.engine.starts, isEmpty);
    expectCleaned(harness);
  });

  test('overlapping VAD chunks are rejected before model loading', () async {
    harness.audio.chunks = [
      PreparedAudio(audioId: 'first', duration: const Duration(seconds: 2)),
      PreparedAudio(
          audioId: 'second',
          duration: const Duration(seconds: 2),
          sourceOffset: const Duration(seconds: 1)),
    ];
    final probe = harness.start();
    await probe.done.future;
    expectFailure(probe, EngineFailureCode.invalidAudio);
    expect(harness.engine.starts, isEmpty);
    expectCleaned(harness);
  });

  test(
      'cancellation during preparation stops the adapter and awaits quiescence before cleanup',
      () async {
    final released = Completer<void>();
    addTearDown(() {
      if (!released.isCompleted) released.complete();
    });
    harness.audio.prepareAction = (signal) async {
      await signal.whenCancelled;
      await released.future;
      signal.throwIfCancelled();
      return [];
    };
    final probe = harness.start();
    await harness.audio.started.future;
    final first = harness.coordinator.cancel('job-1');
    expect(harness.coordinator.cancel('job-1'), same(first));
    expect(harness.audio.signal!.isCancelled, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(harness.audio.cleanedJobs, isEmpty);
    released.complete();
    await first;
    await probe.done.future;
    expect(probe.errors, isEmpty);
    expect(probe.events.last, isA<JobCancelled>());
    expect(harness.engine.starts, isEmpty);
    expectCleaned(harness);
  });

  test(
      'transcription cancellation stops actual engine work and retains only committed segments',
      () async {
    final cleanup = Completer<void>();
    addTearDown(() {
      if (!cleanup.isCompleted) cleanup.complete();
    });
    harness = TranscriptionHarness(engineCleanup: () => cleanup.future);
    final probe = harness.start();
    await harness.engine.waitForStart(0);
    harness.engine.inner.emitSegment(harness.segment(0));
    harness.engine.inner
        .emitSegment(harness.segment(0, segmentId: 'partial', isFinal: false));
    await Future<void>.delayed(Duration.zero);
    final cancellation = harness.coordinator.cancel('job-1');
    expect(harness.coordinator.cancel('job-1'), same(cancellation));
    await Future<void>.delayed(Duration.zero);
    expect(harness.engine.status, EngineStatus.cancelling);
    expect(harness.engine.cancelCalls, 1);
    expect(harness.audio.cleanedJobs, isEmpty);
    cleanup.complete();
    await cancellation;
    await probe.done.future;
    final cancelled = probe.events.last as JobCancelled;
    expect(cancelled.segments.map((event) => event.segment.segmentId),
        ['segment-1']);
    expect(harness.engine.status, EngineStatus.ready);
    expectCleaned(harness);
  });

  test(
      'second coordinator sharing the same engine is rejected without touching the active job',
      () async {
    final probe = harness.start();
    await harness.engine.waitForStart(0);
    final other = TranscriptionCoordinator(
        engine: harness.engine,
        audioPreparation: harness.audio,
        models: harness.models);
    addTearDown(other.dispose);
    final rejected = JobProbe(other.transcribe(
        jobId: 'job-2', sourceId: 'other', tier: ModelTier.fast));
    await rejected.done.future;
    expectFailure(rejected, EngineFailureCode.busy);
    expect(harness.engine.status, EngineStatus.transcribing);
    expect(harness.audio.cleanedJobs, isEmpty);
    await harness.coordinator.cancel('not-the-job');
    expect(harness.engine.cancelCalls, 0);
    harness.engine.inner.complete();
    await probe.done.future;
    expectCleaned(harness);
  });

  test(
      'cleanup completes before success and before another job can be admitted',
      () async {
    final cleanup = Completer<void>();
    final cleaning = Completer<void>();
    addTearDown(() {
      if (!cleanup.isCompleted) cleanup.complete();
    });
    harness.audio.cleanupAction = () async {
      cleaning.complete();
      await cleanup.future;
    };
    final probe = harness.start();
    await harness.engine.waitForStart(0);
    harness.engine.inner.complete();
    await cleaning.future;
    expect(probe.events.whereType<JobCompleted>(), isEmpty);
    final rejected = harness.start(jobId: 'job-2');
    await rejected.done.future;
    expectFailure(rejected, EngineFailureCode.busy);
    cleanup.complete();
    await probe.done.future;
    harness.audio.cleanupAction = null;
    final next = harness.start(jobId: 'job-3');
    await harness.engine.waitForStart(1);
    harness.engine.inner.complete();
    await next.done.future;
    expect(next.errors, isEmpty);
    expectCleaned(harness, count: 2);
  });

  test(
      'subscription cancellation while paused still stops work and cleans the job',
      () async {
    final probe = harness.start();
    await harness.engine.waitForStart(0);
    probe.subscription.pause();
    await probe.subscription.cancel();
    expect(harness.engine.cancelCalls, 1);
    expect(harness.engine.status, EngineStatus.ready);
    expectCleaned(harness);
  });

  test(
      'coordinator disposal cancels the job but leaves the injected engine alive',
      () async {
    final probe = harness.start();
    await harness.engine.waitForStart(0);
    final disposal = harness.coordinator.dispose();
    expect(harness.coordinator.dispose(), same(disposal));
    await disposal;
    await probe.done.future;
    expect(probe.events.last, isA<JobCancelled>());
    expect(harness.engine.status, EngineStatus.ready);
    final rejected = harness.start(jobId: 'after-dispose');
    await rejected.done.future;
    expectFailure(rejected, EngineFailureCode.disposed);
    expectCleaned(harness);
  });

  test(
      'cleanup failure is reported instead of success and releases the engine lease',
      () async {
    harness.audio.cleanupAction =
        () async => throw StateError('cleanup failed');
    final probe = harness.start();
    await harness.engine.waitForStart(0);
    harness.engine.inner.complete();
    await probe.done.future;
    expectFailure(probe, EngineFailureCode.ioError);
    expect(harness.audio.cleanedJobs, hasLength(1));
    harness.audio.cleanupAction = null;
    final next = harness.start(jobId: 'job-2');
    await harness.engine.waitForStart(1);
    harness.engine.inner.complete();
    await next.done.future;
    expect(next.errors, isEmpty);
  });

  for (final malformed in [
    'missing terminal',
    'wrong job',
    'event after terminal'
  ]) {
    test('$malformed is a typed failure with cleanup', () async {
      harness.engine.script = (start) async* {
        switch (malformed) {
          case 'wrong job':
            yield TranscriptionCompleted('wrong-job');
          case 'event after terminal':
            yield TranscriptionCompleted(start.jobId);
            yield TranscriptionProgress(jobId: start.jobId, fraction: 1);
        }
      };
      final probe = harness.start();
      await probe.done.future;
      expectFailure(probe, EngineFailureCode.inferenceFailed);
      expectCleaned(harness);
    });
  }

  test('existing production factory remains honestly unavailable', () async {
    final engine = EngineFactory.createEngine();
    final coordinator = TranscriptionCoordinator(
        engine: engine,
        audioPreparation: harness.audio,
        models: harness.models);
    addTearDown(engine.dispose);
    addTearDown(coordinator.dispose);
    final probe = JobProbe(coordinator.transcribe(
        jobId: 'real', sourceId: 'source-media', tier: ModelTier.fast));
    await probe.done.future;
    expectFailure(probe, EngineFailureCode.unsupported);
    expect(harness.trace, ['cleanup']);
    expectCleaned(harness);
  });
}
