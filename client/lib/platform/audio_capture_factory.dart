import '../../features/transcriber/domain/ports/audio_capture.dart';
import 'audio/capture_factory_native.dart'
    if (dart.library.js_interop) 'audio/capture_factory_web.dart' as platform;

AudioCapture createPlatformAudioCapture() => platform.createPlatformAudioCapture();
