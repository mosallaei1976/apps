import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/transcriber/application/transcription_coordinator.dart';
import 'audio_preparation_factory.dart';
import 'engine_factory.dart';
import 'model_runtime.dart';

/// Builds the current platform composition: a typed unavailable engine, the
/// configured or explicitly unavailable audio-preparation adapter, and platform
/// model verification.
TranscriptionCoordinator createTranscriptionCoordinator(Ref ref) {
  final engine = EngineFactory.createEngine();
  final audioPreparation = createPlatformAudioPreparation();
  unawaited(
    audioPreparation.sweepStaleJobs().catchError((Object _) {
      // Startup cache expiry is best effort and must not block composition.
    }),
  );
  final coordinator = TranscriptionCoordinator(
    engine: engine,
    audioPreparation: audioPreparation,
    models: createVerifiedModelAccess(),
  );
  ref.onDispose(() async {
    await coordinator.dispose();
    await engine.dispose();
    await audioPreparation.dispose();
  });
  return coordinator;
}
