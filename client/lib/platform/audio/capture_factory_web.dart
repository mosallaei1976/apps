import '../../features/transcriber/domain/ports/audio_capture.dart';
import 'unavailable_audio_capture.dart';

AudioCapture createPlatformAudioCapture() => const UnavailableAudioCapture(
      'Microphone capture is not available in the web build.',
    );
