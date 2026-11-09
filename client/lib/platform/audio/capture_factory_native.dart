import 'dart:io';

import '../../features/transcriber/domain/ports/audio_capture.dart';
import 'unavailable_audio_capture.dart';
import 'windows_microphone_capture.dart';

/// Native capture selection. Only Windows has an implemented backend; other
/// native targets report an honest local error until their adapters exist.
AudioCapture createPlatformAudioCapture() {
  if (Platform.isWindows) {
    return WindowsMicrophoneCapture();
  }
  return const UnavailableAudioCapture(
    'Microphone capture is only implemented for Windows in this build.',
  );
}
