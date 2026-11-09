import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/transcriber/application/transcription_coordinator.dart';
import 'engine_factory.dart';
import 'model_runtime.dart';
import 'stub_services.dart';

/// Builds the current platform composition: a typed unavailable engine, an
/// explicit unavailable audio adapter and platform model verification.
TranscriptionCoordinator createTranscriptionCoordinator(Ref ref) {
  final engine = EngineFactory.createEngine();
  final coordinator = TranscriptionCoordinator(
    engine: engine,
    audioPreparation: const UnavailableAudioPreparation(),
    models: createVerifiedModelAccess(),
  );
  ref.onDispose(() async {
    await coordinator.dispose();
    await engine.dispose();
  });
  return coordinator;
}
