import 'dart:async';

import 'package:client/features/transcriber/domain/engine/engine_failure.dart';
import 'package:client/features/transcriber/presentation/transcription_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../application/support/transcription_fakes.dart';
import '../support/fake_audio_capture.dart';

void main() {
  late TranscriptionHarness harness;
  late FakeAudioCapture capture;
  late TranscriptionSessionController controller;

  setUp(() {
    harness = TranscriptionHarness();
    capture = FakeAudioCapture();
    controller = TranscriptionSessionController(harness.coordinator, capture);
  });

  tearDown(() async {
    controller.dispose();
    await harness.dispose();
  });

  test('recording stops into a job using the opaque capture ID', () async {
    harness.audio.chunks = [];

    await controller.startRecording();
    expect(controller.state.phase, TranscriptionPhase.recording);
    expect(capture.startCalls, 1);

    await controller.stopRecording();
    await pumpEventQueue();

    expect(controller.state.phase, TranscriptionPhase.completed);
    expect(harness.trace, contains('prepare:capture-0'));
    expect(capture.stoppedIds, ['capture-0']);
    expect(capture.discardedIds, ['capture-0']);
  });

  test('permission denial fails before any transcription job starts', () async {
    capture.permissionDenied = true;

    await controller.startRecording();
    await pumpEventQueue();

    expect(controller.state.phase, TranscriptionPhase.failed);
    expect(controller.state.failure?.code, EngineFailureCode.permissionDenied);
    expect(harness.trace, isEmpty);
  });

  test('cancelling while recording aborts and removes the capture', () async {
    await controller.startRecording();
    await controller.cancel();

    expect(controller.state.phase, TranscriptionPhase.cancelled);
    expect(capture.cancelledIds, ['capture-0']);
    expect(capture.discardedIds, isEmpty);
    expect(harness.trace, isEmpty);
  });

  test('a failed stop is typed and still discards the capture', () async {
    capture.failStop = true;

    await controller.startRecording();
    await controller.stopRecording();
    await pumpEventQueue();

    expect(controller.state.phase, TranscriptionPhase.failed);
    expect(controller.state.failure?.code, EngineFailureCode.ioError);
    expect(capture.discardedIds, ['capture-0']);
    expect(harness.trace, isEmpty);
  });

  test('cancelling while capture finalizes never starts a job', () async {
    final gate = Completer<void>();
    capture.stopGate = gate;

    await controller.startRecording();
    final stopping = controller.stopRecording();
    await pumpEventQueue();
    expect(controller.state.phase, TranscriptionPhase.active);

    await controller.cancel();
    expect(controller.state.phase, TranscriptionPhase.cancelling);

    gate.complete();
    await stopping;
    await pumpEventQueue();

    expect(controller.state.phase, TranscriptionPhase.cancelled);
    expect(capture.stoppedIds, ['capture-0']);
    expect(capture.discardedIds, ['capture-0']);
    expect(harness.trace, isEmpty);
  });
}
