import 'dart:async';
import 'dart:io';

import 'package:client/features/transcriber/domain/engine/abstract_engine_interface.dart';
import 'package:client/platform/whisper/whisper_engine.dart';
import 'package:client/platform/whisper/whisper_inference_runner.dart';
import 'package:client/platform/whisper/whisper_paths.dart';
import 'package:client/platform/whisper/whisper_toolchain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/fake_whisper_runner.dart';
import 'support/wav_fixture.dart';

Matcher failureWith(EngineFailureCode code) =>
    isA<EngineFailure>().having((failure) => failure.code, 'code', code);

PreparedAudio preparedAudio({
  String audioId = 'job-1',
  Duration duration = const Duration(milliseconds: 100),
}) =>
    PreparedAudio(audioId: audioId, duration: duration);

ModelSpec modelSpec() => ModelSpec(
      id: 'base-q5',
      tier: ModelTier.fast,
      artifactId: 'base-q5',
    );

void main() {
  late Directory temporary;
  late String libraryPath;
  late FakeWhisperRunner runner;
  late WhisperFfiEngine engine;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('whisper-engine-');
    libraryPath = p.join(temporary.path, 'whisper.dll');
    await File(libraryPath).writeAsBytes(const [1, 2, 3], flush: true);

    final model = File(p.join(temporary.path, 'models', 'base-q5.bin'));
    await model.parent.create(recursive: true);
    await model.writeAsBytes(const [4, 5, 6, 7], flush: true);

    final audio = File(p.join(
      temporary.path,
      'persian_transcriber',
      'jobs',
      'job-1',
      'prepared.wav',
    ));
    await audio.parent.create(recursive: true);
    await audio.writeAsBytes(wavBytes(dataLength: 3200), flush: true);

    runner = FakeWhisperRunner();
    engine = WhisperFfiEngine(
      toolchainConfig: WhisperToolchainConfig(
        libraryPath: libraryPath,
        expectedSha256: 'a' * 64,
      ),
      runner: runner,
      paths: WhisperPathResolver(
        applicationSupportDirectory: () async => temporary,
        temporaryDirectory: () async => temporary,
      ),
    );
  });

  tearDown(() async {
    await engine.dispose();
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  Future<void> makeReady() async {
    await engine.initialize();
    await engine.loadModel(modelSpec());
  }

  test('initializes the verified configured library once', () async {
    await engine.initialize();
    expect(engine.status, EngineStatus.initialized);
    expect(
      runner.calls.single,
      'initialize:$libraryPath:${'a' * 64}',
    );
    await engine.initialize();
    expect(runner.calls, hasLength(1));
    expect(engine.status, EngineStatus.initialized);
  });

  test('initialization failure is typed and retryable', () async {
    runner.initializeError = const EngineFailure(
      EngineFailureCode.unsupported,
      'Library failed verification.',
    );
    await expectLater(
      engine.initialize(),
      throwsA(failureWith(EngineFailureCode.unsupported)),
    );
    expect(engine.status, EngineStatus.failed);

    runner.initializeError = null;
    await engine.initialize();
    expect(engine.status, EngineStatus.initialized);
  });

  test('loads only an installed model and reports monotonic progress',
      () async {
    final progress = <ModelLoadProgress>[];
    final subscription = engine.modelLoadProgress.listen(progress.add);
    await engine.initialize();
    await engine.loadModel(modelSpec());
    await Future<void>.delayed(Duration.zero);

    expect(engine.status, EngineStatus.ready);
    expect(progress.map((event) => event.fraction), [0, 1]);
    expect(progress.every((event) => event.modelId == 'base-q5'), isTrue);
    expect(
      runner.calls.last,
      'loadModel:${p.join(temporary.path, 'models', 'base-q5.bin')}',
    );
    await subscription.cancel();
  });

  test('missing model reports modelUnavailable without ready state', () async {
    await File(p.join(temporary.path, 'models', 'base-q5.bin')).delete();
    await engine.initialize();
    await expectLater(
      engine.loadModel(modelSpec()),
      throwsA(failureWith(EngineFailureCode.modelUnavailable)),
    );
    expect(engine.status, EngineStatus.initialized);
    expect(runner.calls, hasLength(1));
  });

  test('emits progress, final segments and completion in order', () async {
    await makeReady();
    final eventsFuture = engine
        .transcribe(
          preparedAudio(),
          jobId: 'job-1',
          options: TranscriptionOptions(),
        )
        .toList();
    await runner.transcribeStarted.future;

    runner.emit(const WhisperInferenceProgress(0.5));
    runner.emit(const WhisperInferenceSegments([
      WhisperInferenceSegment(
        segmentId: 'whisper-segment-0',
        text: 'سلام',
        start: Duration(milliseconds: 10),
        end: Duration(milliseconds: 50),
      ),
    ]));
    runner.emit(const WhisperInferenceCompleted());
    await runner.close();

    final events = await eventsFuture;
    expect(events.map((event) => event.runtimeType), [
      TranscriptionProgress,
      TranscriptSegment,
      TranscriptionProgress,
      TranscriptionCompleted,
    ]);
    final segment = events.whereType<TranscriptSegment>().single;
    expect(segment.jobId, 'job-1');
    expect(segment.text, 'سلام');
    expect(segment.isFinal, isTrue);
    expect(segment.sourceStart(preparedAudio()), const Duration(milliseconds: 10));
    expect(runner.request?.languageCode, 'fa');
    expect(engine.status, EngineStatus.ready);
  });

  test('cancellation is idempotent and emits one cancelled terminal', () async {
    await makeReady();
    final events = <TranscriptionEvent>[];
    final done = Completer<void>();
    engine
        .transcribe(
          preparedAudio(),
          jobId: 'job-1',
          options: TranscriptionOptions(),
        )
        .listen(events.add, onDone: done.complete);
    await runner.transcribeStarted.future;

    final first = engine.cancel('job-1');
    final second = engine.cancel('job-1');
    expect(second, same(first));
    expect(engine.status, EngineStatus.cancelling);
    await first;
    await done.future;

    expect(events.last, isA<TranscriptionCancelled>());
    expect(events.whereType<TranscriptionCancelled>(), hasLength(1));
    expect(runner.cancelled, ['job-1']);
    expect(engine.status, EngineStatus.ready);
    await engine.cancel('job-1');
  });

  test('invalid prepared audio fails before the runner is invoked', () async {
    await makeReady();
    final audio = File(p.join(
      temporary.path,
      'persian_transcriber',
      'jobs',
      'job-1',
      'prepared.wav',
    ));
    await audio.writeAsBytes(const [0, 1, 2, 3], flush: true);

    await expectLater(
      engine.transcribe(
        preparedAudio(),
        jobId: 'job-1',
        options: TranscriptionOptions(),
      ),
      emitsInOrder([
        emitsError(failureWith(EngineFailureCode.invalidAudio)),
        emitsDone,
      ]),
    );
    expect(runner.calls.where((call) => call.startsWith('transcribe')), isEmpty);
    expect(engine.status, EngineStatus.ready);
  });

  test('prepared duration mismatch is rejected', () async {
    await makeReady();
    await expectLater(
      engine.transcribe(
        preparedAudio(duration: const Duration(milliseconds: 200)),
        jobId: 'job-1',
        options: TranscriptionOptions(),
      ),
      emitsInOrder([
        emitsError(failureWith(EngineFailureCode.invalidAudio)),
        emitsDone,
      ]),
    );
  });

  test('runner failures are typed and leave the model reusable', () async {
    await makeReady();
    final completion = expectLater(
      engine.transcribe(
        preparedAudio(),
        jobId: 'job-1',
        options: TranscriptionOptions(),
      ),
      emitsInOrder([
        emitsError(failureWith(EngineFailureCode.inferenceFailed)),
        emitsDone,
      ]),
    );
    await runner.transcribeStarted.future;
    runner.fail(const EngineFailure(
      EngineFailureCode.inferenceFailed,
      'Native decode failed.',
    ));
    await runner.close();
    await completion;
    expect(engine.status, EngineStatus.ready);
  });

  test('busy engine rejects lifecycle and concurrent jobs', () async {
    await makeReady();
    final done = Completer<void>();
    engine
        .transcribe(
          preparedAudio(),
          jobId: 'job-1',
          options: TranscriptionOptions(),
        )
        .listen((_) {}, onDone: done.complete);
    await runner.transcribeStarted.future;

    await expectLater(
      engine.loadModel(modelSpec()),
      throwsA(failureWith(EngineFailureCode.busy)),
    );
    await expectLater(
      engine.transcribe(
        preparedAudio(),
        jobId: 'job-2',
        options: TranscriptionOptions(),
      ),
      emitsInOrder([
        emitsError(failureWith(EngineFailureCode.busy)),
        emitsDone,
      ]),
    );

    await engine.cancel('job-1');
    await done.future;
    expect(engine.status, EngineStatus.ready);
  });

  test('dispose cancels active work, releases the runner and rejects reuse',
      () async {
    await makeReady();
    final events = <TranscriptionEvent>[];
    final done = Completer<void>();
    engine
        .transcribe(
          preparedAudio(),
          jobId: 'job-1',
          options: TranscriptionOptions(),
        )
        .listen(events.add, onDone: done.complete);
    await runner.transcribeStarted.future;

    final disposal = engine.dispose();
    expect(engine.dispose(), same(disposal));
    await disposal;
    await done.future;

    expect(runner.disposed, isTrue);
    expect(events.last, isA<TranscriptionCancelled>());
    expect(engine.status, EngineStatus.disposed);
    await expectLater(
      engine.initialize(),
      throwsA(failureWith(EngineFailureCode.disposed)),
    );
    await expectLater(
      engine.transcribe(
        preparedAudio(),
        jobId: 'job-2',
        options: TranscriptionOptions(),
      ),
      emitsInOrder([
        emitsError(failureWith(EngineFailureCode.disposed)),
        emitsDone,
      ]),
    );
  });
}
