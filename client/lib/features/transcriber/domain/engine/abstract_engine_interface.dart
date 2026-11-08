import 'dart:async';

import 'engine_types.dart';

export 'engine_failure.dart';
export 'engine_types.dart';

abstract interface class AbstractEngineInterface {
  EngineStatus get status;
  Stream<EngineStatus> get statusChanges;
  Stream<ModelLoadProgress> get modelLoadProgress;

  Future<void> initialize();
  Future<void> loadModel(ModelSpec model);
  Future<void> unloadModel();

  Stream<TranscriptionEvent> transcribe(
    PreparedAudio audio, {
    required String jobId,
    required TranscriptionOptions options,
  });

  Future<void> cancel(String jobId);
  Future<void> dispose();
}
