import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../features/transcriber/domain/engine/abstract_engine_interface.dart';
import '../../features/transcriber/domain/ports/cancellation_signal.dart';
import 'model_manifest.dart';

/// Owns the application-private model and resumable-download directories.
///
/// Installed artifacts live in `<root>/models`; `.part` files and their resume
/// metadata live in `<root>/downloads`. Neither directory contains user source
/// media or transcripts, so cleanup here cannot delete user-owned files.
final class ModelStorage {
  ModelStorage({required Future<Directory> Function() rootDirectory})
      : _rootDirectory = rootDirectory;

  final Future<Directory> Function() _rootDirectory;

  Future<File> modelFile(String artifactId) async => File(p.join(
      (await _directory('models')).path, '${_requireId(artifactId)}.bin'));

  Future<File> partialFile(String artifactId) async => File(p.join(
      (await _directory('downloads')).path, '${_requireId(artifactId)}.part'));

  Future<File> partialMetadataFile(String artifactId) async => File(p.join(
      (await _directory('downloads')).path,
      '${_requireId(artifactId)}.part.json'));

  /// Verifies that the installed artifact has the exact manifest size and
  /// SHA-256. Missing, truncated or modified artifacts are rejected.
  Future<void> verify(
    ModelArtifact artifact, {
    required CancellationSignal cancellation,
  }) async {
    final file = await modelFile(artifact.id);
    await _verifyFile(file, artifact, cancellation: cancellation);
  }

  /// Verifies the resumable `.part` file and atomically promotes it to the
  /// installed model location.
  ///
  /// Callers must ensure that no active engine is loading or using the
  /// destination artifact before replacing it.
  Future<void> install(
    ModelArtifact artifact, {
    required CancellationSignal cancellation,
  }) async {
    final part = await partialFile(artifact.id);
    try {
      await _verifyFile(part, artifact, cancellation: cancellation);
      cancellation.throwIfCancelled();

      final target = await modelFile(artifact.id);
      final backup = File('${target.path}.old');
      if (await backup.exists()) await backup.delete();
      if (await target.exists()) await target.rename(backup.path);
      try {
        await part.rename(target.path);
      } catch (error) {
        if (await backup.exists()) {
          await backup.rename(target.path);
        }
        rethrow;
      }
      try {
        if (await backup.exists()) await backup.delete();
      } on FileSystemException {
        // The promoted artifact is usable; a stale backup is harmless.
      }
      try {
        await _deleteQuietly(await partialMetadataFile(artifact.id));
      } on FileSystemException {
        // Stale resume metadata is discarded by the next download attempt.
      }
    } on EngineFailure {
      rethrow;
    } on FileSystemException {
      throw const EngineFailure(
          EngineFailureCode.ioError, 'Could not install the model artifact.');
    }
  }

  /// Removes the installed artifact and any resumable download state.
  ///
  /// Callers must not delete an artifact that is currently loaded by an engine.
  Future<void> delete(String artifactId) async {
    try {
      final model = await modelFile(artifactId);
      await _deleteQuietly(model);
      await _deleteQuietly(File('${model.path}.old'));
      await _deleteQuietly(await partialFile(artifactId));
      await _deleteQuietly(await partialMetadataFile(artifactId));
    } on FileSystemException {
      throw const EngineFailure(
          EngineFailureCode.ioError, 'Could not delete the model artifact.');
    }
  }

  /// Removes abandoned `.part` files and resume metadata older than [maxAge].
  ///
  /// Runs at startup, before downloads or after an explicit cache action. It
  /// never touches installed artifacts and never follows links outside the
  /// managed download directory.
  Future<int> sweepStaleDownloads({
    Duration maxAge = const Duration(days: 7),
    DateTime? now,
  }) async {
    final directory = await _directory('downloads');
    final cutoff = (now ?? DateTime.now()).subtract(maxAge);
    var removed = 0;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.endsWith('.part') &&
          !name.endsWith('.part.json') &&
          !name.endsWith('.part.json.tmp')) {
        continue;
      }
      try {
        final modified = (await entity.stat()).modified;
        if (modified.isBefore(cutoff)) {
          await entity.delete();
          removed++;
        }
      } on FileSystemException {
        // Keep the file; the next sweep retries the deletion.
      }
    }
    return removed;
  }

  Future<Map<String, Object?>?> readPartialMetadata(String artifactId) async {
    try {
      final file = await partialMetadataFile(artifactId);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      throw const EngineFailure(
          EngineFailureCode.ioError, 'Could not read download metadata.');
    }
  }

  Future<void> writePartialMetadata(
    String artifactId,
    Map<String, Object?> metadata,
  ) async {
    try {
      final file = await partialMetadataFile(artifactId);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(metadata), flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    } on FileSystemException {
      throw const EngineFailure(
          EngineFailureCode.ioError, 'Could not save download metadata.');
    }
  }

  Future<void> deletePartialMetadata(String artifactId) async {
    try {
      await _deleteQuietly(await partialMetadataFile(artifactId));
    } on FileSystemException {
      throw const EngineFailure(
          EngineFailureCode.ioError, 'Could not delete download metadata.');
    }
  }

  Future<Directory> _directory(String name) async {
    final root = await _rootDirectory();
    final directory = Directory(p.join(root.path, name));
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> _verifyFile(
    File file,
    ModelArtifact artifact, {
    required CancellationSignal cancellation,
  }) async {
    cancellation.throwIfCancelled();
    final stat = await FileStat.stat(file.path);
    if (stat.type != FileSystemEntityType.file) {
      throw EngineFailure(EngineFailureCode.modelUnavailable,
          'Model artifact ${artifact.id} is not installed.');
    }
    if (stat.size != artifact.byteLength) {
      throw EngineFailure(EngineFailureCode.modelUnavailable,
          'Model artifact ${artifact.id} has an unexpected size.');
    }

    final String digest;
    try {
      digest = await _sha256(file, cancellation);
    } on EngineFailure {
      rethrow;
    } on FileSystemException {
      throw EngineFailure(EngineFailureCode.ioError,
          'Could not read model artifact ${artifact.id}.');
    }
    cancellation.throwIfCancelled();
    if (digest != artifact.sha256) {
      throw EngineFailure(EngineFailureCode.modelUnavailable,
          'Model artifact ${artifact.id} failed SHA-256 verification.');
    }
  }

  Future<String> _sha256(File file, CancellationSignal cancellation) async {
    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);
    await for (final chunk in file.openRead()) {
      cancellation.throwIfCancelled();
      input.add(chunk);
    }
    input.close();
    return sink.value.toString();
  }

  Future<void> _deleteQuietly(File file) async {
    if (await file.exists()) await file.delete();
  }
}

final class _DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value =>
      _value ?? (throw StateError('SHA-256 produced no digest'));

  @override
  void add(Digest data) => _value = data;

  @override
  void close() {}
}

final _artifactIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');

String _requireId(String value) {
  if (!_artifactIdPattern.hasMatch(value)) {
    throw ArgumentError.value(
        value, 'artifactId', 'Unsafe artifact identifier');
  }
  return value;
}
