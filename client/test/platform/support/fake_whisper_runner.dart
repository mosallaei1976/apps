import 'dart:async';

import 'package:client/features/transcriber/domain/engine/engine_failure.dart';
import 'package:client/platform/whisper/whisper_inference_runner.dart';

/// Deterministic runner used to exercise the engine without a real model/DLL.
final class FakeWhisperRunner implements WhisperInferenceRunner {
  final List<String> calls = <String>[];
  final List<String> cancelled = <String>[];
  final Completer<void> transcribeStarted = Completer<void>();

  EngineFailure? initializeError;
  EngineFailure? loadModelError;
  bool disposed = false;
  WhisperInferenceRequest? request;

  StreamController<WhisperInferenceEvent>? _job;
  bool _jobClosed = false;

  @override
  Future<void> initialize({
    required String libraryPath,
    required String expectedSha256,
  }) async {
    calls.add('initialize:$libraryPath:$expectedSha256');
    final error = initializeError;
    if (error != null) throw error;
  }

  @override
  Future<void> loadModel({required String modelPath}) async {
    calls.add('loadModel:$modelPath');
    final error = loadModelError;
    if (error != null) throw error;
  }

  @override
  Stream<WhisperInferenceEvent> transcribe(WhisperInferenceRequest request) {
    this.request = request;
    calls.add('transcribe:${request.requestId}');
    _jobClosed = false;
    _job = StreamController<WhisperInferenceEvent>();
    if (!transcribeStarted.isCompleted) transcribeStarted.complete();
    return _job!.stream;
  }

  void emit(WhisperInferenceEvent event) {
    final job = _job;
    if (job == null || _jobClosed) {
      throw StateError('No active fake inference.');
    }
    job.add(event);
  }

  void fail(Object error) {
    final job = _job;
    if (job == null || _jobClosed) {
      throw StateError('No active fake inference.');
    }
    job.addError(error);
  }

  Future<void> close() async {
    if (_jobClosed) return;
    _jobClosed = true;
    await _job?.close();
  }

  @override
  Future<void> cancel(String requestId) async {
    cancelled.add(requestId);
    if (_job == null || _jobClosed || request?.requestId != requestId) return;
    _job!.add(const WhisperInferenceCancelled());
    await close();
  }

  @override
  Future<void> unloadModel() async {
    calls.add('unloadModel');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await close();
  }
}
