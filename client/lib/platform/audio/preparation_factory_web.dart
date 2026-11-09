import '../stub_services.dart';
import 'managed_audio_preparation.dart';

/// Browser builds have no local FFmpeg process or native worker isolate.
ManagedAudioPreparation createPlatformAudioPreparation() =>
    const UnavailableAudioPreparation(
      'FFmpeg audio preparation is not available in the web build.',
    );
