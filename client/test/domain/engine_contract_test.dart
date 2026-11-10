import 'dart:async';

import 'package:client/features/transcriber/domain/abstract_engine_interface.dart'
    as legacy;
import 'package:client/features/transcriber/domain/engine/abstract_engine_interface.dart';
import 'package:client/platform/engine_factory.dart';
import 'package:client/platform/stub_engines.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/controlled_engine.dart';

Matcher failureWith(EngineFailureCode code) =>
    isA<EngineFailure>().having((failure) => failure.code, 'code', code);

PreparedAudio preparedAudio({Duration offset = Duration.zero}) => PreparedAudio(
      audioId: 'audio-1',
      duration: const Duration(seconds: 5),
      sourceOffset: offset,
    );

ModelSpec modelSpec() => ModelSpec(
      id: 'base-q5-v1',
      tier: ModelTier.fast,
      artifactId: 'verified-base-q5-v1',
    );

TranscriptSegment segment({
  String jobId = 'job-1',
  String text = 'سلام',
  bool isFinal = true,
}) =>
    TranscriptSegment(
      jobId: jobId,
      segmentId: 'segment-1',
      text: text,
      start: const Duration(seconds: 1),
      end: const Duration(seconds: 2),
      isFinal: isFinal,
    );

void main() {
  group('Domain DTO invariants', () {
    test('quantized model profiles retain distinct tiers and formats', () {
      final base = modelSpec();
      final small = ModelSpec(
        id: 'small-int8-v1',
        tier: ModelTier.balanced,
        artifactId: 'verified-small-int8-v1',
        quantization: ModelQuantization.q8_0,
      );
      expect(base.quantization, ModelQuantization.q5_1);
      expect(base.approximateDownloadBytes, 80000000);
      expect(small.quantization, ModelQuantization.q8_0);
      expect(small.approximateDownloadBytes, 200000000);
    });

    test('opaque identifiers and language must not be blank', () {
      final invalidConstructors = <Object Function()>[
        () => ModelSpec(id: ' ', tier: ModelTier.fast, artifactId: 'artifact'),
        () => ModelSpec(id: 'model', tier: ModelTier.fast, artifactId: ''),
        () => PreparedAudio(audioId: '', duration: const Duration(seconds: 1)),
        () => ModelLoadProgress(modelId: ' '),
        () => TranscriptionOptions(languageCode: ''),
        () => TranscriptionCompleted(' '),
        () => TranscriptionCancelled(''),
        () => TranscriptionProgress(jobId: ''),
        () => segment(jobId: ''),
        () => TranscriptSegment(
              jobId: 'job',
              segmentId: '',
              text: '',
              start: Duration.zero,
              end: Duration.zero,
              isFinal: true,
            ),
      ];
      for (final create in invalidConstructors) {
        expect(create, throwsArgumentError);
      }
    });

    test('prepared audio requires positive duration and nonnegative offset',
        () {
      for (final duration in [Duration.zero, const Duration(seconds: -1)]) {
        expect(
          () => PreparedAudio(audioId: 'audio', duration: duration),
          throwsArgumentError,
        );
      }
      expect(
        () => preparedAudio(offset: const Duration(microseconds: -1)),
        throwsArgumentError,
      );
    });

    test('progress and confidence accept unknown and normalized values', () {
      expect(ModelLoadProgress(modelId: 'model').fraction, isNull);
      expect(TranscriptionProgress(jobId: 'job').fraction, isNull);
      expect(segment().confidence, isNull);
      for (final fraction in [0.0, 0.5, 1.0]) {
        expect(ModelLoadProgress(modelId: 'model', fraction: fraction).fraction,
            fraction);
        expect(TranscriptionProgress(jobId: 'job', fraction: fraction).fraction,
            fraction);
      }
      for (final fraction in [-0.1, 1.1, double.nan, double.infinity]) {
        expect(() => ModelLoadProgress(modelId: 'model', fraction: fraction),
            throwsRangeError);
        expect(() => TranscriptionProgress(jobId: 'job', fraction: fraction),
            throwsRangeError);
        expect(
          () => TranscriptSegment(
            jobId: 'job',
            segmentId: 'segment',
            text: '',
            start: Duration.zero,
            end: Duration.zero,
            isFinal: true,
            confidence: fraction,
          ),
          throwsRangeError,
        );
      }
    });

    test('timestamps reject negative/reversed ranges and apply offset once',
        () {
      for (final range in [
        (const Duration(seconds: -1), Duration.zero),
        (const Duration(seconds: 2), const Duration(seconds: 1)),
      ]) {
        expect(
          () => TranscriptSegment(
            jobId: 'job',
            segmentId: 'segment',
            text: '',
            start: range.$1,
            end: range.$2,
            isFinal: true,
          ),
          throwsArgumentError,
        );
      }
      final audio = preparedAudio(offset: const Duration(seconds: 30));
      final result = segment();
      expect(result.start, const Duration(seconds: 1));
      expect(result.sourceStart(audio), const Duration(seconds: 31));
      expect(result.sourceEnd(audio), const Duration(seconds: 32));
      final tooShort = PreparedAudio(
        audioId: 'short',
        duration: const Duration(milliseconds: 500),
      );
      expect(() => result.sourceStart(tooShort), throwsArgumentError);
      expect(() => result.sourceEnd(tooShort), throwsArgumentError);
    });

    test('sealed transcription events support exhaustive handling', () {
      final events = <TranscriptionEvent>[
        segment(isFinal: false),
        TranscriptionProgress(jobId: 'job-1', fraction: 0.5),
        TranscriptionCompleted('job-1'),
        TranscriptionCancelled('job-1'),
      ];
      expect(
          events.map((event) => switch (event) {
                TranscriptSegment(:final isFinal) =>
                  isFinal ? 'final' : 'partial',
                TranscriptionProgress() => 'progress',
                TranscriptionCompleted() => 'completed',
                TranscriptionCancelled() => 'cancelled',
              }),
          ['partial', 'progress', 'completed', 'cancelled']);
      expect(TranscriptionOptions().languageCode, 'fa');
      expect(TranscriptionOptions().emitPartials, isTrue);
      expect(
          const EngineFailure(EngineFailureCode.ioError, 'Read failed')
              .toString(),
          'EngineFailure(ioError): Read failed');
    });

    test('old import re-exports the same interface rather than a competitor',
        () async {
      final AbstractEngineInterface engine = EngineFactory.createEngine();
      final legacy.AbstractEngineInterface sameContract = engine;
      expect(sameContract, same(engine));
      await engine.dispose();
    });
  });

  for (final entry in <String, AbstractEngineInterface Function()>{
    'native': NativeFfiEngine.new,
    'web': WasmWebWorkerEngine.new,
    'factory': EngineFactory.createEngine,
  }.entries) {
    group('${entry.key} unavailable scaffold', () {
      late AbstractEngineInterface engine;
      setUp(() => engine = entry.value());
      tearDown(() => engine.dispose());

      test(
          'reports typed unavailability without claiming runtime/model readiness',
          () async {
        expect(engine.status, EngineStatus.uninitialized);
        expect(engine.statusChanges.isBroadcast, isTrue);
        expect(engine.modelLoadProgress.isBroadcast, isTrue);
        final statuses = <EngineStatus>[];
        final progress = <ModelLoadProgress>[];
        final statusSubscription = engine.statusChanges.listen(statuses.add);
        final progressSubscription =
            engine.modelLoadProgress.listen(progress.add);
        await expectLater(engine.initialize(),
            throwsA(failureWith(EngineFailureCode.unsupported)));
        expect(engine.status, EngineStatus.failed);
        await expectLater(engine.loadModel(modelSpec()),
            throwsA(failureWith(EngineFailureCode.notReady)));
        await engine.unloadModel();
        await Future<void>.delayed(Duration.zero);
        expect(statuses, [EngineStatus.failed]);
        expect(progress, isEmpty);
        await statusSubscription.cancel();
        await progressSubscription.cancel();
      });

      test('rejected transcription emits one typed stream error then closes',
          () async {
        final stream = engine.transcribe(preparedAudio(),
            jobId: 'job-1', options: TranscriptionOptions());
        expect(stream.isBroadcast, isFalse);
        await expectLater(
            stream,
            emitsInOrder([
              emitsError(failureWith(EngineFailureCode.notReady)),
              emitsDone,
            ]));
        expect(engine.status, EngineStatus.uninitialized);
      });

      test('rejects empty job IDs and cancellation is harmless without work',
          () async {
        await expectLater(
          engine.transcribe(preparedAudio(),
              jobId: '', options: TranscriptionOptions()),
          emitsInOrder([
            emitsError(failureWith(EngineFailureCode.invalidRequest)),
            emitsDone
          ]),
        );
        await engine.cancel('unknown');
        await engine.cancel('unknown');
        expect(engine.status, EngineStatus.uninitialized);
      });

      test('dispose closes both streams, is idempotent and rejects reuse',
          () async {
        final statusEvents = engine.statusChanges.toList();
        final progressEvents = engine.modelLoadProgress.toList();
        final first = engine.dispose();
        expect(engine.dispose(), same(first));
        await first;
        expect(await statusEvents, [EngineStatus.disposed]);
        expect(await progressEvents, isEmpty);
        await engine.cancel('job-1');
        await expectLater(engine.initialize(),
            throwsA(failureWith(EngineFailureCode.disposed)));
        await expectLater(engine.loadModel(modelSpec()),
            throwsA(failureWith(EngineFailureCode.disposed)));
        await expectLater(engine.unloadModel(),
            throwsA(failureWith(EngineFailureCode.disposed)));
        await expectLater(
          engine.transcribe(preparedAudio(),
              jobId: 'job-2', options: TranscriptionOptions()),
          emitsInOrder(
              [emitsError(failureWith(EngineFailureCode.disposed)), emitsDone]),
        );
      });
    });
  }

  group('Successful-job contract using a controlled test adapter', () {
    late ControlledEngine engine;
    setUp(() async {
      engine = ControlledEngine();
      await engine.initialize();
      await engine.loadModel(modelSpec());
    });
    tearDown(() => engine.dispose());

    test('model lifecycle reports monotonic progress and supports unloading',
        () async {
      final events = <ModelLoadProgress>[];
      final subscription = engine.modelLoadProgress.listen(events.add);
      await engine.unloadModel();
      expect(engine.status, EngineStatus.initialized);
      await engine.loadModel(modelSpec());
      await Future<void>.delayed(Duration.zero);
      expect(events.map((event) => event.fraction), [0, 1]);
      expect(events.every((event) => event.modelId == modelSpec().id), isTrue);
      expect(engine.status, EngineStatus.ready);
      await engine.initialize();
      expect(engine.status, EngineStatus.ready);
      await subscription.cancel();
    });

    test('partial revisions retain segment identity and success closes once',
        () async {
      final events = <TranscriptionEvent>[];
      final completion = engine
          .transcribe(preparedAudio(),
              jobId: 'job-1', options: TranscriptionOptions())
          .forEach(events.add);
      engine.emitSegment(segment(text: 'س', isFinal: false));
      engine.emitSegment(segment(text: 'سلام', isFinal: false));
      engine.emitSegment(segment());
      expect(() => engine.emitSegment(segment()), throwsStateError);
      engine.complete();
      await completion;
      expect(events.whereType<TranscriptSegment>().map((event) => event.text),
          ['س', 'سلام', 'سلام']);
      expect(
          events
              .whereType<TranscriptSegment>()
              .map((event) => event.segmentId)
              .toSet(),
          {'segment-1'});
      expect(events.last, isA<TranscriptionCompleted>());
      expect(events.whereType<TranscriptionCompleted>(), hasLength(1));
      expect(engine.status, EngineStatus.ready);
    });

    test('partials can be disabled while final segments are still emitted',
        () async {
      final completion = engine
          .transcribe(preparedAudio(),
              jobId: 'job-1',
              options: TranscriptionOptions(emitPartials: false))
          .toList();
      engine.emitSegment(segment(isFinal: false));
      engine.emitSegment(segment());
      engine.complete();
      final events = await completion;
      expect(events.whereType<TranscriptSegment>(), hasLength(1));
      expect((events.first as TranscriptSegment).isFinal, isTrue);
      expect(events.last, isA<TranscriptionCompleted>());
    });

    test('admission occurs on listen; busy rejection preserves the active job',
        () async {
      final unlistened = engine.transcribe(preparedAudio(),
          jobId: 'job-2', options: TranscriptionOptions());
      expect(engine.status, EngineStatus.ready);
      final active = engine
          .transcribe(preparedAudio(),
              jobId: 'job-1', options: TranscriptionOptions())
          .toList();
      await expectLater(
          unlistened,
          emitsInOrder(
              [emitsError(failureWith(EngineFailureCode.busy)), emitsDone]));
      expect(engine.status, EngineStatus.transcribing);
      await expectLater(
          engine.unloadModel(), throwsA(failureWith(EngineFailureCode.busy)));
      await expectLater(engine.loadModel(modelSpec()),
          throwsA(failureWith(EngineFailureCode.busy)));
      await engine.cancel('wrong-job');
      expect(engine.status, EngineStatus.transcribing);
      engine.complete();
      expect((await active).single, isA<TranscriptionCompleted>());
    });

    test(
        'typed processing failure closes without a completion and permits reuse',
        () async {
      final completion = expectLater(
        engine.transcribe(preparedAudio(),
            jobId: 'job-1', options: TranscriptionOptions()),
        emitsInOrder([
          emitsError(failureWith(EngineFailureCode.processingTimeout)),
          emitsDone
        ]),
      );
      engine.fail(const EngineFailure(
          EngineFailureCode.processingTimeout, 'Timed out.'));
      await completion;
      expect(engine.status, EngineStatus.ready);
      final next = engine
          .transcribe(preparedAudio(),
              jobId: 'job-2', options: TranscriptionOptions())
          .toList();
      engine.complete();
      expect((await next).single.jobId, 'job-2');
    });
  });

  group('Cancellation contract using a controlled test adapter', () {
    late ControlledEngine engine;
    late Completer<void> cleanup;
    setUp(() async {
      cleanup = Completer<void>();
      engine = ControlledEngine(cleanup: () => cleanup.future);
      await engine.initialize();
      await engine.loadModel(modelSpec());
    });
    tearDown(() async {
      if (!cleanup.isCompleted) cleanup.complete();
      await engine.dispose();
    });

    test('repeated cancellation waits for cleanup and terminates normally once',
        () async {
      final events = engine
          .transcribe(preparedAudio(),
              jobId: 'job-1', options: TranscriptionOptions())
          .toList();
      final cancellation = engine.cancel('job-1');
      expect(engine.cancel('job-1'), same(cancellation));
      expect(engine.status, EngineStatus.cancelling);
      await expectLater(
        engine.transcribe(preparedAudio(),
            jobId: 'job-2', options: TranscriptionOptions()),
        emitsInOrder(
            [emitsError(failureWith(EngineFailureCode.busy)), emitsDone]),
      );
      cleanup.complete();
      await cancellation;
      expect((await events).single, isA<TranscriptionCancelled>());
      expect(engine.status, EngineStatus.ready);
    });

    test(
        'subscription cancellation waits for cleanup before admitting a new job',
        () async {
      final subscription = engine
          .transcribe(preparedAudio(),
              jobId: 'job-1', options: TranscriptionOptions())
          .listen((_) {});
      final cancellation = subscription.cancel();
      expect(engine.status, EngineStatus.cancelling);
      cleanup.complete();
      await cancellation;
      expect(engine.status, EngineStatus.ready);
      final next = engine
          .transcribe(preparedAudio(),
              jobId: 'job-2', options: TranscriptionOptions())
          .toList();
      engine.complete();
      expect((await next).single, isA<TranscriptionCompleted>());
    });

    test('dispose rejects new work immediately and waits for active cleanup',
        () async {
      final events = engine
          .transcribe(preparedAudio(),
              jobId: 'job-1', options: TranscriptionOptions())
          .toList();
      final disposal = engine.dispose();
      expect(engine.dispose(), same(disposal));
      await expectLater(engine.initialize(),
          throwsA(failureWith(EngineFailureCode.disposed)));
      await expectLater(
        engine.transcribe(preparedAudio(),
            jobId: 'job-2', options: TranscriptionOptions()),
        emitsInOrder(
            [emitsError(failureWith(EngineFailureCode.disposed)), emitsDone]),
      );
      cleanup.complete();
      await disposal;
      expect((await events).single, isA<TranscriptionCancelled>());
      expect(engine.status, EngineStatus.disposed);
    });
  });
}
