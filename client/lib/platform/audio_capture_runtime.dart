import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/transcriber/domain/ports/audio_capture.dart';
import 'audio_capture_factory.dart';

/// Builds the platform microphone capture adapter for the composition root.
///
/// The adapter owns only application-private temporary files and is disposed
/// with the provider scope.
AudioCapture createAudioCapture(Ref ref) {
  final capture = createPlatformAudioCapture();
  ref.onDispose(() async => capture.dispose());
  return capture;
}
