import '../features/transcriber/domain/engine/abstract_engine_interface.dart';
import 'stub_engines.dart';
import 'whisper/isolate_whisper_runner.dart';
import 'whisper/whisper_engine.dart';
import 'whisper/whisper_paths.dart';
import 'whisper/whisper_toolchain.dart';

/// Native whisper.cpp inference is enabled only by explicit local configuration.
/// There is no bundled, downloaded or PATH-discovered library.
AbstractEngineInterface createEngine() {
  try {
    final config = WhisperToolchainConfig.fromEnvironment();
    if (config == null) {
      return NativeFfiEngine(
        'Whisper.cpp inference is not configured. Set '
        'PERSIAN_TRANSCRIBER_WHISPER_SHA256 and optionally an absolute '
        'PERSIAN_TRANSCRIBER_WHISPER_PATH to a verified local whisper.dll.',
      );
    }
    return WhisperFfiEngine(
      toolchainConfig: config,
      runner: IsolateWhisperInferenceRunner(),
      paths: WhisperPathResolver(),
    );
  } on Object {
    return NativeFfiEngine(
      'Whisper.cpp inference configuration is invalid or incomplete.',
    );
  }
}
