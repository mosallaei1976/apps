import 'dart:async';
import 'dart:io';

import 'package:client/features/transcriber/domain/engine/engine_failure.dart';
import 'package:client/features/transcriber/domain/ports/cancellation_signal.dart';
import 'package:client/platform/audio/ffmpeg_audio_preparation.dart';
import 'package:client/platform/audio/ffmpeg_toolchain.dart';
import 'package:client/platform/audio/wav_format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/ffmpeg_test_support.dart';
import 'support/wav_fixture.dart';

void main() {
  late FakeFfmpeg fake;
  late Directory temporary;

  setUpAll(() async {
    fake = await compileFakeFfmpeg();
  });

  tearDownAll(() async {
    await fake.dispose();
  });

  setUp(() async {
    await fake.clearControls();
    temporary = await Directory.systemTemp.createTemp('ffmpeg-preparation-');
  });

  tearDown(() async {
    await fake.clearControls();
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  FfmpegToolchainConfig config() => FfmpegToolchainConfig(
        executablePath: fake.executable.path,
        expectedSha256: fake.sha256,
        selfTestTimeout: const Duration(seconds: 15),
        conversionTimeout: const Duration(seconds: 15),
      );

  FfmpegAudioPreparation createPreparation() {
    final preparation = FfmpegAudioPreparation(
      toolchainConfig: config(),
      temporaryDirectory: () async => temporary,
    );
    addTearDown(preparation.dispose);
    return preparation;
  }

  Directory captureDirectory(String captureId) => Directory(p.join(
        temporary.path,
        'persian_transcriber',
        'captures',
        captureId,
      ));

  File captureFile(String captureId) => File(
        p.join(captureDirectory(captureId).path, 'capture.wav'),
      );

  Future<void> createCapture(String captureId) async {
    final file = captureFile(captureId);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(wavBytes(dataLength: 4800), flush: true);
  }

  Directory jobsRoot() => Directory(
        p.join(temporary.path, 'persian_transcriber', 'jobs'),
      );

  Directory jobDirectory(String jobId) =>
      Directory(p.join(jobsRoot().path, jobId));

  File preparedFile(String jobId) =>
      File(p.join(jobDirectory(jobId).path, 'prepared.wav'));

  test('prepares a managed capture into the job scope and cleans it up',
      () async {
    await createCapture('capture-1');
    final preparation = createPreparation();

    final chunks = await preparation.prepare(
      sourceId: 'capture-1',
      jobId: 'job-1',
      cancellation: _Cancellation(),
    );

    expect(chunks, hasLength(1));
    expect(chunks.single.audioId, 'job-1');
    expect(chunks.single.sourceOffset, Duration.zero);
    expect(chunks.single.duration, const Duration(milliseconds: 100));

    final output = preparedFile('job-1');
    expect(await output.exists(), isTrue);
    expect(WavFormat.read(output).duration, chunks.single.duration);
    expect(await captureFile('capture-1').exists(), isTrue);

    await preparation.cleanup('job-1');
    expect(await jobDirectory('job-1').exists(), isFalse);
    await preparation.cleanup('job-1');
  });

  test('cleanup without preparation is idempotent', () async {
    final preparation = createPreparation();

    await preparation.cleanup('job-missing');
    await preparation.cleanup('job-missing');
  });

  test('rejects unsafe capture and job identifiers', () async {
    await createCapture('capture-1');
    final preparation = createPreparation();

    for (final (sourceId, jobId) in <(String, String)>[
      ('../outside', 'job-1'),
      ('capture-1', '../outside'),
      ('capture-1', ''),
      ('', 'job-1'),
      ('capture-1/child', 'job-1'),
    ]) {
      await expectLater(
        preparation.prepare(
          sourceId: sourceId,
          jobId: jobId,
          cancellation: _Cancellation(),
        ),
        throwsA(isA<EngineFailure>().having(
          (error) => error.code,
          'code',
          EngineFailureCode.invalidRequest,
        )),
      );
    }

    expect(await captureFile('capture-1').exists(), isTrue);
    expect(await jobsRoot().exists(), isFalse);
  });

  test('a missing or empty capture is reported as invalid audio', () async {
    final preparation = createPreparation();

    await expectLater(
      preparation.prepare(
        sourceId: 'capture-missing',
        jobId: 'job-1',
        cancellation: _Cancellation(),
      ),
      throwsA(isA<EngineFailure>().having(
        (error) => error.code,
        'code',
        EngineFailureCode.invalidAudio,
      )),
    );
    expect(await jobDirectory('job-1').exists(), isFalse);

    final file = captureFile('capture-empty');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(<int>[], flush: true);
    await expectLater(
      preparation.prepare(
        sourceId: 'capture-empty',
        jobId: 'job-2',
        cancellation: _Cancellation(),
      ),
      throwsA(isA<EngineFailure>().having(
        (error) => error.code,
        'code',
        EngineFailureCode.invalidAudio,
      )),
    );
    expect(await jobDirectory('job-2').exists(), isFalse);
  });

  test('rejects a conversion failure and removes the job directory', () async {
    await createCapture('capture-1');
    final preparation = createPreparation();
    await preparation.prepare(
      sourceId: 'capture-1',
      jobId: 'job-warm',
      cancellation: _Cancellation(),
    );
    await preparation.cleanup('job-warm');

    await fake.setFailure(5);
    await expectLater(
      preparation.prepare(
        sourceId: 'capture-1',
        jobId: 'job-fail',
        cancellation: _Cancellation(),
      ),
      throwsA(isA<EngineFailure>().having(
        (error) => error.code,
        'code',
        EngineFailureCode.invalidAudio,
      )),
    );
    expect(await jobDirectory('job-fail').exists(), isFalse);
  });

  test('rejects invalid FFmpeg output and removes the job directory', () async {
    await createCapture('capture-1');
    final preparation = createPreparation();
    await preparation.prepare(
      sourceId: 'capture-1',
      jobId: 'job-warm',
      cancellation: _Cancellation(),
    );
    await preparation.cleanup('job-warm');

    await fake.setInvalidWav();
    await expectLater(
      preparation.prepare(
        sourceId: 'capture-1',
        jobId: 'job-invalid',
        cancellation: _Cancellation(),
      ),
      throwsA(isA<EngineFailure>().having(
        (error) => error.code,
        'code',
        EngineFailureCode.invalidAudio,
      )),
    );
    expect(await jobDirectory('job-invalid').exists(), isFalse);
  });

  test('an already-cancelled prepare creates no job files', () async {
    await createCapture('capture-1');
    final preparation = createPreparation();
    final cancellation = _Cancellation()..cancel();

    await expectLater(
      preparation.prepare(
        sourceId: 'capture-1',
        jobId: 'job-cancelled',
        cancellation: cancellation,
      ),
      throwsA(isA<EngineFailure>().having(
        (error) => error.code,
        'code',
        EngineFailureCode.cancelled,
      )),
    );
    expect(await jobDirectory('job-cancelled').exists(), isFalse);
  });

  test('cancellation during conversion is scoped to one request', () async {
    await createCapture('capture-1');
    final preparation = createPreparation();
    await preparation.prepare(
      sourceId: 'capture-1',
      jobId: 'job-warm',
      cancellation: _Cancellation(),
    );
    await preparation.cleanup('job-warm');

    await fake.setDelay(const Duration(seconds: 3));
    final cancellation = _Cancellation();
    final pending = preparation.prepare(
      sourceId: 'capture-1',
      jobId: 'job-cancelled',
      cancellation: cancellation,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    cancellation.cancel();

    await expectLater(
      pending,
      throwsA(isA<EngineFailure>().having(
        (error) => error.code,
        'code',
        EngineFailureCode.cancelled,
      )),
    );
    expect(await jobDirectory('job-cancelled').exists(), isFalse);

    await fake.clearControls();
    final chunks = await preparation.prepare(
      sourceId: 'capture-1',
      jobId: 'job-after-cancel',
      cancellation: _Cancellation(),
    );
    expect(chunks.single.duration, const Duration(milliseconds: 100));
    await preparation.cleanup('job-after-cancel');
  });

  test('a second concurrent prepare is rejected as busy', () async {
    await createCapture('capture-1');
    final preparation = createPreparation();
    await fake.setDelay(const Duration(seconds: 2));
    final cancellation = _Cancellation();

    final first = preparation.prepare(
      sourceId: 'capture-1',
      jobId: 'job-first',
      cancellation: cancellation,
    );
    for (var attempt = 0; attempt < 100; attempt++) {
      if (await jobDirectory('job-first').exists()) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    await expectLater(
      preparation.prepare(
        sourceId: 'capture-1',
        jobId: 'job-second',
        cancellation: _Cancellation(),
      ),
      throwsA(isA<EngineFailure>().having(
        (error) => error.code,
        'code',
        EngineFailureCode.busy,
      )),
    );
    await expectLater(
      preparation.cleanup('job-first'),
      throwsA(isA<EngineFailure>().having(
        (error) => error.code,
        'code',
        EngineFailureCode.busy,
      )),
    );

    cancellation.cancel();
    await expectLater(first, throwsA(isA<EngineFailure>()));
    expect(await jobDirectory('job-first').exists(), isFalse);
  });

  test('sweeps only job scopes older than 24 hours', () async {
    await createCapture('capture-1');
    final oldFile = preparedFile('job-old');
    await oldFile.parent.create(recursive: true);
    await oldFile.writeAsBytes(wavBytes(), flush: true);
    final now = DateTime.now();
    await oldFile.setLastModified(now.subtract(const Duration(days: 2)));

    final newFile = preparedFile('job-new');
    await newFile.parent.create(recursive: true);
    await newFile.writeAsBytes(wavBytes(), flush: true);
    await newFile.setLastModified(now.subtract(const Duration(hours: 1)));

    final emptyDirectory = jobDirectory('job-empty');
    await emptyDirectory.create(recursive: true);

    final preparation = createPreparation();
    await preparation.sweepStaleJobs(now: now);

    expect(await jobDirectory('job-old').exists(), isFalse);
    expect(await jobDirectory('job-new').exists(), isTrue);
    expect(await jobDirectory('job-empty').exists(), isTrue);
    expect(await captureFile('capture-1').exists(), isTrue);
  });

  test('sweep rejects a non-positive age', () async {
    final preparation = createPreparation();

    await expectLater(
      preparation.sweepStaleJobs(maxAge: Duration.zero),
      throwsArgumentError,
    );
  });

  test('dispose releases the worker and rejects new preparation', () async {
    await createCapture('capture-1');
    final preparation = createPreparation();
    await preparation.prepare(
      sourceId: 'capture-1',
      jobId: 'job-1',
      cancellation: _Cancellation(),
    );
    await preparation.cleanup('job-1');

    await preparation.dispose();
    await preparation.dispose();

    await expectLater(
      preparation.prepare(
        sourceId: 'capture-1',
        jobId: 'job-2',
        cancellation: _Cancellation(),
      ),
      throwsA(isA<EngineFailure>().having(
        (error) => error.code,
        'code',
        EngineFailureCode.disposed,
      )),
    );
    await preparation.cleanup('job-2');
  });
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
        EngineFailureCode.cancelled,
        'Cancelled by test.',
      );
    }
  }
}
