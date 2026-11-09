import 'dart:async';

import 'package:client/features/transcriber/domain/engine/engine_failure.dart';
import 'package:client/features/transcriber/domain/ports/audio_capture.dart';

/// Deterministic capture adapter for presentation and application tests.
final class FakeAudioCapture implements AudioCapture {
  FakeAudioCapture({
    this.permissionDenied = false,
    this.failStart = false,
    this.failStop = false,
  });

  bool permissionDenied;
  bool failStart;
  bool failStop;

  final trace = <String>[];
  final stoppedIds = <String>[];
  final cancelledIds = <String>[];
  final discardedIds = <String>[];
  int startCalls = 0;
  bool disposed = false;
  String? activeId;
  Completer<void>? stopGate;
  int _sequence = 0;

  @override
  Future<String> start() async {
    if (permissionDenied) {
      throw const EngineFailure(
        EngineFailureCode.permissionDenied,
        'Microphone permission was denied.',
      );
    }
    if (failStart) {
      throw const EngineFailure(
        EngineFailureCode.ioError,
        'Microphone capture could not start.',
      );
    }
    final captureId = 'capture-${_sequence++}';
    activeId = captureId;
    startCalls++;
    trace.add('start:$captureId');
    return captureId;
  }

  @override
  Future<void> stop(String captureId) async {
    await stopGate?.future;
    if (failStop) {
      throw const EngineFailure(
        EngineFailureCode.ioError,
        'Microphone capture could not be finalized.',
      );
    }
    activeId = null;
    stoppedIds.add(captureId);
    trace.add('stop:$captureId');
  }

  @override
  Future<void> cancel(String captureId) async {
    activeId = null;
    cancelledIds.add(captureId);
    trace.add('cancel:$captureId');
  }

  @override
  Future<void> discard(String captureId) async {
    discardedIds.add(captureId);
    trace.add('discard:$captureId');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    trace.add('dispose');
  }
}
