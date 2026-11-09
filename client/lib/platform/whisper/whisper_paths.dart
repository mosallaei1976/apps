import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/transcriber/domain/engine/engine_failure.dart';
import '../../features/transcriber/domain/engine/engine_types.dart';
import 'whisper_toolchain.dart';

typedef DirectoryProvider = Future<Directory> Function();

/// Resolves only application-managed paths for the native engine.
///
/// Paths never cross the domain port. A missing or unsafe identifier produces a
/// typed error instead of a filesystem lookup outside the managed roots.
final class WhisperPathResolver {
  WhisperPathResolver({
    DirectoryProvider? applicationSupportDirectory,
    DirectoryProvider? temporaryDirectory,
  })  : _applicationSupportDirectory =
            applicationSupportDirectory ?? getApplicationSupportDirectory,
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final DirectoryProvider _applicationSupportDirectory;
  final DirectoryProvider _temporaryDirectory;

  /// The explicit absolute path, or the app-relative managed location.
  Future<String> libraryPath(WhisperToolchainConfig config) async {
    final explicit = config.libraryPath;
    if (explicit != null) return explicit;
    final root = await _applicationSupportDirectory();
    return p.join(root.path, 'whisper', 'whisper.dll');
  }

  Future<String> modelPath(ModelSpec model) async {
    final id = _requireId(model.artifactId, 'model artifact');
    final root = await _applicationSupportDirectory();
    final file = File(p.join(root.path, 'models', '$id.bin'));
    final stat = await _statOrNull(file);
    if (stat == null ||
        stat.type != FileSystemEntityType.file ||
        stat.size <= 0) {
      throw EngineFailure(
        EngineFailureCode.modelUnavailable,
        'Model artifact $id is not installed.',
      );
    }
    return file.path;
  }

  Future<String> preparedAudioPath(PreparedAudio audio) async {
    final id = _requireId(audio.audioId, 'prepared audio');
    final root = await _temporaryDirectory();
    final file = File(p.join(
      root.path,
      'persian_transcriber',
      'jobs',
      id,
      'prepared.wav',
    ));
    final stat = await _statOrNull(file);
    if (stat == null ||
        stat.type != FileSystemEntityType.file ||
        stat.size <= 0) {
      throw const EngineFailure(
        EngineFailureCode.invalidAudio,
        'Prepared audio is missing or empty.',
      );
    }
    return file.path;
  }

  String _requireId(String value, String label) {
    if (!_idPattern.hasMatch(value)) {
      throw EngineFailure(
        label == 'prepared audio'
            ? EngineFailureCode.invalidAudio
            : EngineFailureCode.modelUnavailable,
        'Invalid $label identifier.',
      );
    }
    return value;
  }

  Future<FileStat?> _statOrNull(File file) async {
    try {
      return await FileStat.stat(file.path);
    } on FileSystemException {
      return null;
    }
  }
}

final _idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
