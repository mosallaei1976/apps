import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/transcriber/application/transcription_coordinator.dart';
import 'engine_factory.dart';
import 'stub_services.dart';

/// Builds the current platform composition: a typed unavailable engine plus
/// explicit unavailable audio/model adapters.
TranscriptionCoordinator createTranscriptionCoordinator(Ref ref) {
  final engine = EngineFactory.createEngine();
  final coordinator = TranscriptionCoordinator(
    engine: engine,
    audioPreparation: const UnavailableAudioPreparation(),
    models: const UnavailableVerifiedModelAccess(),
  );
  ref.onDispose(() async {
    await coordinator.dispose();
    await engine.dispose();
  });
  return coordinator;
}
