import 'dart:async';
import 'dart:io';

import '../../features/transcriber/domain/engine/abstract_engine_interface.dart';
import '../../features/transcriber/domain/ports/cancellation_signal.dart';
import 'model_manifest.dart';
import 'model_storage.dart';

enum ModelDownloadPhase { downloading, verifying }

final class ModelDownloadProgress {
  const ModelDownloadProgress({
    required this.artifact,
    required this.phase,
    required this.receivedBytes,
    required this.totalBytes,
  });

  final ModelArtifact artifact;
  final ModelDownloadPhase phase;
  final int receivedBytes;
  final int totalBytes;

  double get fraction => totalBytes == 0 ? 0 : receivedBytes / totalBytes;
}

/// A minimal HTTP response needed by the resumable downloader.
///
/// Keeping this separate from `dart:io` lets the download state machine be
/// tested without a network and keeps browser builds away from native APIs.
final class ModelDownloadResponse {
  const ModelDownloadResponse({
    required this.statusCode,
    required this.body,
    required this.abort,
    this.contentLength,
    this.etag,
    this.lastModified,
    this.contentRange,
  });

  final int statusCode;
  final Stream<List<int>> body;
  final Future<void> Function() abort;
  final int? contentLength;
  final String? etag;
  final String? lastModified;
  final String? contentRange;
}

abstract interface class ModelDownloadTransport {
  Future<ModelDownloadResponse> send(
    Uri uri, {
    int? rangeStart,
    String? ifRange,
  });

  Future<void> close();
}

/// Downloads a pinned artifact with Range resume, validator checks and
/// SHA-256 verification before promotion.
final class ModelDownloader {
  ModelDownloader({
    required ModelStorage storage,
    required ModelDownloadTransport transport,
  })  : _storage = storage,
        _transport = transport;

  final ModelStorage _storage;
  final ModelDownloadTransport _transport;

  /// Downloads or resumes [artifact] and installs it after verification.
  ///
  /// Cancellation preserves the `.part` file and resume metadata. Corrupt
  /// artifacts are never promoted, and a changed remote artifact is detected
  /// through the stored ETag/Last-Modified validator plus the final SHA-256.
  Future<void> download(
    ModelArtifact artifact, {
    required CancellationSignal cancellation,
    void Function(ModelDownloadProgress progress)? onProgress,
  }) async {
    cancellation.throwIfCancelled();
    for (var attempt = 0; attempt < 2; attempt++) {
      final prepared = await _preparePartial(artifact);
      final resumed = prepared.offset > 0;
      cancellation.throwIfCancelled();
      if (prepared.offset < artifact.byteLength) {
        await _transfer(
          artifact,
          prepared.offset,
          prepared.metadata,
          cancellation,
          onProgress,
        );
      }

      onProgress?.call(ModelDownloadProgress(
        artifact: artifact,
        phase: ModelDownloadPhase.verifying,
        receivedBytes: artifact.byteLength,
        totalBytes: artifact.byteLength,
      ));
      try {
        await _storage.install(artifact, cancellation: cancellation);
        return;
      } on EngineFailure catch (error) {
        if (error.code != EngineFailureCode.modelUnavailable) rethrow;
        await _discardPartial(artifact);
        if (attempt > 0 || !resumed) rethrow;
        // A resumed file may belong to an older remote artifact. Restart once
        // from an empty part file before reporting an integrity failure.
      }
    }
    throw const EngineFailure(EngineFailureCode.modelUnavailable,
        'Model download could not be verified.');
  }

  Future<void> _transfer(
    ModelArtifact artifact,
    int offset,
    Map<String, Object?>? metadata,
    CancellationSignal cancellation,
    void Function(ModelDownloadProgress progress)? onProgress,
  ) async {
    var start = offset;
    var resumeMetadata = metadata;
    for (var send = 0; send < 2; send++) {
      cancellation.throwIfCancelled();
      final response = await _send(artifact, start, resumeMetadata);
      final status = response.statusCode;

      if (start > 0 && status == 206) {
        final range = _parseContentRange(response.contentRange);
        final validatorChanged = _validatorChanged(resumeMetadata, response);
        if (range == null ||
            range.start != start ||
            range.total != artifact.byteLength ||
            validatorChanged) {
          await response.abort();
          await _discardPartial(artifact);
          start = 0;
          resumeMetadata = null;
          continue;
        }
        resumeMetadata =
            _metadata(artifact, response, previous: resumeMetadata);
        await _storage.writePartialMetadata(artifact.id, resumeMetadata);
        await _consume(
          artifact,
          response,
          start,
          append: true,
          cancellation: cancellation,
          onProgress: onProgress,
        );
        return;
      }

      if (status == 200) {
        if (response.contentLength != null &&
            response.contentLength != artifact.byteLength) {
          await response.abort();
          throw const EngineFailure(EngineFailureCode.modelUnavailable,
              'The remote model artifact does not match the manifest size.');
        }
        resumeMetadata = _metadata(artifact, response);
        await _storage.writePartialMetadata(artifact.id, resumeMetadata);
        await _consume(
          artifact,
          response,
          0,
          append: false,
          cancellation: cancellation,
          onProgress: onProgress,
        );
        return;
      }

      if (start > 0 && status == 416) {
        await response.abort();
        await _discardPartial(artifact);
        start = 0;
        resumeMetadata = null;
        continue;
      }

      await response.abort();
      throw EngineFailure(
          EngineFailureCode.ioError, 'The model server returned HTTP $status.');
    }
    throw const EngineFailure(EngineFailureCode.ioError,
        'The model server did not provide a usable artifact response.');
  }

  Future<ModelDownloadResponse> _send(
    ModelArtifact artifact,
    int start,
    Map<String, Object?>? metadata,
  ) async {
    try {
      return await _transport.send(
        artifact.source,
        rangeStart: start > 0 ? start : null,
        ifRange: start > 0 ? _ifRange(metadata) : null,
      );
    } on EngineFailure {
      rethrow;
    } on Object {
      throw const EngineFailure(
          EngineFailureCode.ioError, 'Could not reach the model server.');
    }
  }

  Future<void> _consume(
    ModelArtifact artifact,
    ModelDownloadResponse response,
    int start, {
    required bool append,
    required CancellationSignal cancellation,
    required void Function(ModelDownloadProgress progress)? onProgress,
  }) async {
    final part = await _storage.partialFile(artifact.id);
    final IOSink sink;
    try {
      if (append && await part.length() != start) {
        throw const EngineFailure(EngineFailureCode.ioError,
            'The model download state changed before resuming.');
      }
      sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
    } on EngineFailure {
      rethrow;
    } on FileSystemException {
      throw const EngineFailure(
          EngineFailureCode.ioError, 'Could not write the model download.');
    }
    var received = start;
    unawaited(cancellation.whenCancelled.then((_) async {
      try {
        await response.abort();
      } on Object {
        // The response may already be closed.
      }
    }));
    try {
      await for (final chunk in response.body) {
        cancellation.throwIfCancelled();
        if (received + chunk.length > artifact.byteLength) {
          throw const EngineFailure(EngineFailureCode.modelUnavailable,
              'The remote model artifact is larger than the manifest entry.');
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(ModelDownloadProgress(
          artifact: artifact,
          phase: ModelDownloadPhase.downloading,
          receivedBytes: received,
          totalBytes: artifact.byteLength,
        ));
      }
      await sink.flush();
    } on EngineFailure {
      rethrow;
    } on Object {
      cancellation.throwIfCancelled();
      throw const EngineFailure(
          EngineFailureCode.ioError, 'The model download was interrupted.');
    } finally {
      try {
        await sink.close();
      } on Object {
        // Flush already succeeded; preserve the primary download result.
      }
    }

    cancellation.throwIfCancelled();
    if (received != artifact.byteLength) {
      throw const EngineFailure(EngineFailureCode.ioError,
          'The model download ended early and can be resumed.');
    }
  }

  Future<({int offset, Map<String, Object?>? metadata})> _preparePartial(
      ModelArtifact artifact) async {
    try {
      final part = await _storage.partialFile(artifact.id);
      final metadata = _validMetadata(
          await _storage.readPartialMetadata(artifact.id), artifact);
      if (!await part.exists()) {
        if (metadata != null) {
          await _storage.deletePartialMetadata(artifact.id);
        }
        return (offset: 0, metadata: null);
      }
      final length = await part.length();
      if (length == 0 || length > artifact.byteLength || metadata == null) {
        await _discardPartial(artifact);
        return (offset: 0, metadata: null);
      }
      return (offset: length, metadata: metadata);
    } on FileSystemException {
      throw const EngineFailure(EngineFailureCode.ioError,
          'Could not read the model download state.');
    }
  }

  Map<String, Object?>? _validMetadata(
    Map<String, Object?>? metadata,
    ModelArtifact artifact,
  ) {
    if (metadata == null) return null;
    if (metadata['artifactId'] != artifact.id ||
        metadata['version'] != artifact.version ||
        metadata['sha256'] != artifact.sha256 ||
        metadata['byteLength'] != artifact.byteLength ||
        metadata['source'] != artifact.source.toString()) {
      return null;
    }
    return metadata;
  }

  Map<String, Object?> _metadata(
    ModelArtifact artifact,
    ModelDownloadResponse response, {
    Map<String, Object?>? previous,
  }) {
    return {
      'artifactId': artifact.id,
      'version': artifact.version,
      'sha256': artifact.sha256,
      'byteLength': artifact.byteLength,
      'source': artifact.source.toString(),
      if (response.etag != null)
        'etag': response.etag
      else if (previous?['etag'] != null)
        'etag': previous!['etag'],
      if (response.lastModified != null)
        'lastModified': response.lastModified
      else if (previous?['lastModified'] != null)
        'lastModified': previous!['lastModified'],
    };
  }

  String? _ifRange(Map<String, Object?>? metadata) {
    final etag = metadata?['etag'];
    if (etag is String && etag.isNotEmpty && !etag.startsWith('W/')) {
      return etag;
    }
    final lastModified = metadata?['lastModified'];
    return lastModified is String && lastModified.isNotEmpty
        ? lastModified
        : null;
  }

  bool _validatorChanged(
    Map<String, Object?>? metadata,
    ModelDownloadResponse response,
  ) {
    final expectedEtag = metadata?['etag'];
    if (expectedEtag is String &&
        expectedEtag.isNotEmpty &&
        !expectedEtag.startsWith('W/') &&
        response.etag != null) {
      return expectedEtag != response.etag;
    }
    final expectedModified = metadata?['lastModified'];
    if (expectedModified is String &&
        expectedModified.isNotEmpty &&
        response.lastModified != null) {
      return expectedModified != response.lastModified;
    }
    return false;
  }

  Future<void> _discardPartial(ModelArtifact artifact) async {
    try {
      final part = await _storage.partialFile(artifact.id);
      if (await part.exists()) await part.delete();
      await _storage.deletePartialMetadata(artifact.id);
    } on Object {
      // Best effort; the next download attempt discards or overwrites it.
    }
  }
}

final _contentRangePattern = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$');

({int start, int end, int total})? _parseContentRange(String? value) {
  if (value == null) return null;
  final match = _contentRangePattern.firstMatch(value.trim());
  if (match == null) return null;
  final start = int.parse(match.group(1)!);
  final end = int.parse(match.group(2)!);
  final total = int.parse(match.group(3)!);
  if (end < start) return null;
  return (start: start, end: end, total: total);
}
