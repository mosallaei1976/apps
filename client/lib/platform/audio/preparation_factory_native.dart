import '../stub_services.dart';
import 'ffmpeg_audio_preparation.dart';
import 'ffmpeg_toolchain.dart';
import 'managed_audio_preparation.dart';

/// Native audio preparation is enabled only by an explicit local FFmpeg
/// configuration. There is no bundled, downloaded or PATH-discovered binary.
ManagedAudioPreparation createPlatformAudioPreparation() {
  try {
    final config = FfmpegToolchainConfig.fromEnvironment();
    if (config == null) {
      return const UnavailableAudioPreparation(
        'FFmpeg audio preparation is not configured. Set '
        'PERSIAN_TRANSCRIBER_FFMPEG_PATH and '
        'PERSIAN_TRANSCRIBER_FFMPEG_SHA256 to a verified local binary.',
      );
    }
    return FfmpegAudioPreparation(toolchainConfig: config);
  } on Object {
    return const UnavailableAudioPreparation(
      'FFmpeg audio preparation configuration is invalid or incomplete.',
    );
  }
}
