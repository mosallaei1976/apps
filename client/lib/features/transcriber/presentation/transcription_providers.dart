import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/transcription_coordinator.dart';
import '../domain/ports/audio_capture.dart';
import 'transcription_session_controller.dart';

/// Injected by the composition root so presentation never constructs a
/// concrete engine, recorder or other infrastructure adapter.
final transcriptionCoordinatorProvider = Provider<TranscriptionCoordinator>(
  (ref) => throw UnimplementedError(
    'transcriptionCoordinatorProvider must be overridden at the composition root.',
  ),
);

final audioCaptureProvider = Provider<AudioCapture>(
  (ref) => throw UnimplementedError(
    'audioCaptureProvider must be overridden at the composition root.',
  ),
);

final transcriptionSessionProvider = StateNotifierProvider<
    TranscriptionSessionController, TranscriptionSessionState>((ref) {
  return TranscriptionSessionController(
    ref.watch(transcriptionCoordinatorProvider),
    ref.watch(audioCaptureProvider),
  );
});
