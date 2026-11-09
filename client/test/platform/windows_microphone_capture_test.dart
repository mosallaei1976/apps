import 'dart:io';

import 'package:client/features/transcriber/domain/engine/engine_failure.dart';
import 'package:client/platform/audio/windows_microphone_capture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';

final class FakeAudioRecorder extends AudioRecorder {
  FakeAudioRecorder({
    this.permission = true,
    this.supportsWav = true,
    this.startFailures = 0,
    this.bytesOnStop = 100,
    this.returnNullOnStop = false,
  });

  bool permission;
  bool supportsWav;
  int startFailures;
  int bytesOnStop;
  bool returnNullOnStop;

  final configs = <RecordConfig>[];
  String? startPath;
  int stopCalls = 0;
  int cancelCalls = 0;
  int disposeCalls = 0;

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) async => supportsWav;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    configs.add(config);
    if (startFailures > 0) {
      startFailures--;
      throw StateError('device rejected the requested format');
    }
    startPath = path;
  }

  @override
  Future<String?> stop() async {
    stopCalls++;
    if (returnNullOnStop || startPath == null) return null;
    final file = File(startPath!);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(
      List<int>.filled(bytesOnStop, 0),
      flush: true,
    );
    return file.path;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

void main() {
  late Directory temporary;
  late FakeAudioRecorder recorder;
  late WindowsMicrophoneCapture capture;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('capture-test-');
    recorder = FakeAudioRecorder();
    capture = WindowsMicrophoneCapture(
      temporaryDirectory: () async => temporary,
      recorderFactory: () => recorder,
    );
  });

  tearDown(() async {
    await capture.dispose();
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  Directory captureDirectory(String captureId) => Directory(p.join(
        temporary.path,
        'persian_transcriber',
        'captures',
        captureId,
      ));

  test('start requests 16 kHz mono WAV under the managed capture directory',
      () async {
    final captureId = await capture.start();

    expect(recorder.configs, hasLength(1));
    expect(recorder.configs.single.encoder, AudioEncoder.wav);
    expect(recorder.configs.single.sampleRate, 16000);
    expect(recorder.configs.single.numChannels, 1);
    expect(await captureDirectory(captureId).exists(), isTrue);
    expect(p.basename(captureDirectory(captureId).path), captureId);
  });

  test('falls back to 48 kHz stereo when the device rejects 16 kHz mono',
      () async {
    recorder.startFailures = 1;

    final captureId = await capture.start();

    expect(recorder.configs, hasLength(2));
    expect(recorder.configs.last.sampleRate, 48000);
    expect(recorder.configs.last.numChannels, 2);
    expect(await captureDirectory(captureId).exists(), isTrue);
  });

  test('cleans up and reports a typed failure when both capture formats fail',
      () async {
    recorder.startFailures = 2;

    await expectLater(
      capture.start(),
      throwsA(isA<EngineFailure>()
          .having((error) => error.code, 'code', EngineFailureCode.ioError)),
    );
    final captures = Directory(p.join(
      temporary.path,
      'persian_transcriber',
      'captures',
    ));
    expect(await captures.list().toList(), isEmpty);
    expect(recorder.cancelCalls, 2);
  });

  test('denied permission is reported without starting the recorder', () async {
    recorder.permission = false;

    await expectLater(
      capture.start(),
      throwsA(isA<EngineFailure>().having(
          (error) => error.code, 'code', EngineFailureCode.permissionDenied)),
    );
    expect(recorder.configs, isEmpty);
  });

  test('unsupported WAV encoder is reported explicitly', () async {
    recorder.supportsWav = false;

    await expectLater(
      capture.start(),
      throwsA(isA<EngineFailure>()
          .having((error) => error.code, 'code', EngineFailureCode.unsupported)),
    );
    expect(recorder.configs, isEmpty);
  });

  test('a second start is rejected while a capture is active', () async {
    await capture.start();

    await expectLater(
      capture.start(),
      throwsA(isA<EngineFailure>()
          .having((error) => error.code, 'code', EngineFailureCode.busy)),
    );
  });

  test('stop finalizes audio and discard removes the managed directory',
      () async {
    final captureId = await capture.start();
    final file = File(p.join(captureDirectory(captureId).path, 'capture.wav'));

    await capture.stop(captureId);

    expect(recorder.stopCalls, 1);
    expect(await file.exists(), isTrue);
    expect(await file.length(), greaterThan(44));

    await capture.discard(captureId);
    expect(await captureDirectory(captureId).exists(), isFalse);

    await capture.discard(captureId);
  });

  test('stop is idempotent for an already stopped capture', () async {
    final captureId = await capture.start();
    await capture.stop(captureId);
    await capture.stop(captureId);

    expect(recorder.stopCalls, 1);
  });

  test('stop rejects a capture without audio and removes its directory',
      () async {
    recorder.bytesOnStop = 44;
    final captureId = await capture.start();

    await expectLater(
      capture.stop(captureId),
      throwsA(isA<EngineFailure>().having(
          (error) => error.code, 'code', EngineFailureCode.invalidAudio)),
    );
    expect(await captureDirectory(captureId).exists(), isFalse);
  });

  test('stop rejects a null recorder path', () async {
    recorder.returnNullOnStop = true;
    final captureId = await capture.start();

    await expectLater(
      capture.stop(captureId),
      throwsA(isA<EngineFailure>().having(
          (error) => error.code, 'code', EngineFailureCode.invalidAudio)),
    );
    expect(await captureDirectory(captureId).exists(), isFalse);
  });

  test('cancel aborts the recorder and removes the capture directory',
      () async {
    final captureId = await capture.start();

    await capture.cancel(captureId);

    expect(recorder.cancelCalls, 1);
    expect(await captureDirectory(captureId).exists(), isFalse);
  });

  test('dispose cancels an active capture and releases the recorder', () async {
    final captureId = await capture.start();

    await capture.dispose();
    await capture.dispose();

    expect(recorder.cancelCalls, 1);
    expect(recorder.disposeCalls, 1);
    expect(await captureDirectory(captureId).exists(), isFalse);
  });

  test('rejects unsafe capture identifiers', () async {
    await expectLater(
      capture.discard('../outside'),
      throwsA(isA<EngineFailure>().having(
          (error) => error.code, 'code', EngineFailureCode.invalidRequest)),
    );
  });
}
