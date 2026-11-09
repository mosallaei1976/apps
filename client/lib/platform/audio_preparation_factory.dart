import 'audio/managed_audio_preparation.dart';
import 'audio/preparation_factory_native.dart'
    if (dart.library.js_interop) 'audio/preparation_factory_web.dart'
    as platform;

ManagedAudioPreparation createPlatformAudioPreparation() =>
    platform.createPlatformAudioPreparation();
