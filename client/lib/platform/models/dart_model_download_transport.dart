import 'dart:io';

import 'model_download.dart';

/// `dart:io` implementation of the resumable-download transport.
///
/// This adapter is native-only; browser builds never import it.
final class DartModelDownloadTransport implements ModelDownloadTransport {
  DartModelDownloadTransport({HttpClient? client})
      : _client = client ?? HttpClient();

  final HttpClient _client;
  bool _closed = false;

  @override
  Future<ModelDownloadResponse> send(
    Uri uri, {
    int? rangeStart,
    String? ifRange,
  }) async {
    if (_closed) {
      throw StateError('The model download transport is closed.');
    }
    final request = await _client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    if (rangeStart != null) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$rangeStart-');
    }
    if (ifRange != null) {
      request.headers.set(HttpHeaders.ifRangeHeader, ifRange);
    }
    final response = await request.close();
    return ModelDownloadResponse(
      statusCode: response.statusCode,
      contentLength: response.contentLength < 0 ? null : response.contentLength,
      etag: response.headers.value(HttpHeaders.etagHeader),
      lastModified: response.headers.value(HttpHeaders.lastModifiedHeader),
      contentRange: response.headers.value(HttpHeaders.contentRangeHeader),
      body: response,
      abort: () async {
        try {
          request.abort();
        } on Object {
          // The request may already be complete or aborted.
        }
      },
    );
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close(force: true);
  }
}
