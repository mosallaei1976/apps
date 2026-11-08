import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/transcription_coordinator.dart';
import 'transcription_session_controller.dart';

/// Injected by the composition root so presentation never constructs a
/// concrete engine or infrastructure adapter.
final transcriptionCoordinatorProvider = Provider<TranscriptionCoordinator>(
  (ref) => throw UnimplementedError(
    'transcriptionCoordinatorProvider must be overridden at the composition root.',
  ),
);

final transcriptionSessionProvider = StateNotifierProvider<
    TranscriptionSessionController, TranscriptionSessionState>((ref) {
  return TranscriptionSessionController(
    ref.watch(transcriptionCoordinatorProvider),
  );
});
