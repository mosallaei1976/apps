import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../features/transcriber/domain/engine/engine_failure.dart';

/// Explicit, locally configured whisper.cpp dynamic library.
///
/// There is deliberately no PATH lookup, package-manager discovery, download or
/// bundled guess. A configured path must be absolute. When the path is omitted
/// but a digest is supplied, the engine resolves the app-relative managed
/// location `<application support>/whisper/whisper.dll`.
final class WhisperToolchainConfig {
  WhisperToolchainConfig({
    String? libraryPath,
    required String expectedSha256,
  })  : libraryPath =
            libraryPath == null ? null : _validateLibraryPath(libraryPath),
        expectedSha256 = _validateSha256(expectedSha256);

  static const String pathEnvironmentVariable =
      'PERSIAN_TRANSCRIBER_WHISPER_PATH';
  static const String sha256EnvironmentVariable =
      'PERSIAN_TRANSCRIBER_WHISPER_SHA256';

  static const String managedRelativePath = 'whisper/whisper.dll';

  /// Absolute path to an explicitly configured binary, or null for the
  /// app-relative managed location.
  final String? libraryPath;

  /// Exact lowercase SHA-256 digest of the trusted binary.
  final String expectedSha256;

  /// Reads the explicit local whisper.cpp configuration.
  ///
  /// Returns null only when both variables are absent. A half-configured or
  /// malformed environment fails with [FormatException] so the composition root
  /// can fall back to an honest unavailable engine instead of guessing.
  static WhisperToolchainConfig? fromEnvironment([
    Map<String, String>? environment,
  ]) {
    final values = environment ?? Platform.environment;
    final rawPath = values[pathEnvironmentVariable]?.trim();
    final rawHash = values[sha256EnvironmentVariable]?.trim();
    final hasPath = rawPath != null && rawPath.isNotEmpty;
    final hasHash = rawHash != null && rawHash.isNotEmpty;
    if (!hasPath && !hasHash) return null;
    if (!hasHash) {
      throw const FormatException(
        'A SHA-256 digest is required for the configured whisper.cpp binary.',
      );
    }
    return WhisperToolchainConfig(
      libraryPath: hasPath ? rawPath : null,
      expectedSha256: rawHash,
    );
  }

  static String _validateLibraryPath(String value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, 'libraryPath', 'Must not be empty');
    }
    if (!p.isAbsolute(value)) {
      throw ArgumentError.value(
        value,
        'libraryPath',
        'Must be an absolute path; PATH search is not allowed',
      );
    }
    if (!p.isAbsolute(p.normalize(value))) {
      throw ArgumentError.value(
        value,
        'libraryPath',
        'Must remain an absolute path after normalization',
      );
    }
    return value;
  }

  static String _validateSha256(String value) {
    final normalized = value.trim().toLowerCase();
    if (!_sha256Pattern.hasMatch(normalized)) {
      throw ArgumentError.value(
        value,
        'expectedSha256',
        'Must be exactly 64 hexadecimal characters',
      );
    }
    return normalized;
  }
}

/// Verifies that [path] is an existing non-empty file with the exact digest.
///
/// This runs inside the inference worker before any native symbol is resolved.
Future<void> verifyWhisperLibrary({
  required String path,
  required String expectedSha256,
}) async {
  if (!p.isAbsolute(path)) {
    throw const EngineFailure(
      EngineFailureCode.unsupported,
      'The whisper.cpp library path must be absolute.',
    );
  }
  if (!_sha256Pattern.hasMatch(expectedSha256)) {
    throw const EngineFailure(
      EngineFailureCode.unsupported,
      'The whisper.cpp library digest is malformed.',
    );
  }

  final file = File(path);
  FileStat stat;
  try {
    stat = await file.stat();
  } on FileSystemException {
    throw const EngineFailure(
      EngineFailureCode.unsupported,
      'The configured whisper.cpp library could not be read.',
    );
  }
  if (stat.type != FileSystemEntityType.file) {
    throw const EngineFailure(
      EngineFailureCode.unsupported,
      'The configured whisper.cpp library does not exist or is not a file.',
    );
  }
  if (stat.size <= 0) {
    throw const EngineFailure(
      EngineFailureCode.unsupported,
      'The configured whisper.cpp library is empty.',
    );
  }

  final String digest;
  try {
    digest = await _sha256(file);
  } on FileSystemException {
    throw const EngineFailure(
      EngineFailureCode.unsupported,
      'The configured whisper.cpp library could not be hashed.',
    );
  }
  if (digest != expectedSha256) {
    throw const EngineFailure(
      EngineFailureCode.unsupported,
      'The configured whisper.cpp library failed SHA-256 verification.',
    );
  }
}

Future<String> _sha256(File file) async {
  final sink = _DigestSink();
  final input = sha256.startChunkedConversion(sink);
  await for (final chunk in file.openRead()) {
    input.add(chunk);
  }
  input.close();
  final digest = sink.value;
  if (digest == null) {
    throw const FileSystemException('SHA-256 produced no digest.');
  }
  return digest.toString().toLowerCase();
}

final class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    value = data;
  }

  @override
  void close() {}
}

final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
