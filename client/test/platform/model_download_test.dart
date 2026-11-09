import 'dart:async';
import 'dart:io';

import 'package:client/features/transcriber/domain/engine/abstract_engine_interface.dart';
import 'package:client/platform/models/model_download.dart';
import 'package:client/platform/models/model_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/model_fixtures.dart';

typedef _Request = ({Uri uri, int? rangeStart, String? ifRange});

final class _FakeTransport implements ModelDownloadTransport {
  _FakeTransport(this.responses);

  final List<FutureOr<ModelDownloadResponse> Function()> responses;
  final requests = <_Request>[];
  int aborts = 0;

  @override
  Future<ModelDownloadResponse> send(
    Uri uri, {
    int? rangeStart,
    String? ifRange,
  }) async {
    requests.add((uri: uri, rangeStart: rangeStart, ifRange: ifRange));
    if (responses.isEmpty) {
      throw StateError('No scripted response remains.');
    }
    return await responses.removeAt(0)();
  }

  @override
  Future<void> close() async {}
}

ModelDownloadResponse _response({
  int statusCode = 200,
  required List<int> bytes,
  int? contentLength,
  String? etag,
  String? lastModified,
  String? contentRange,
  Stream<List<int>>? body,
  Future<void> Function()? abort,
}) =>
    ModelDownloadResponse(
      statusCode: statusCode,
      contentLength: contentLength ?? bytes.length,
      etag: etag,
      lastModified: lastModified,
      contentRange: contentRange,
      body: body ?? _chunked(bytes),
      abort: abort ?? () async {},
    );

Stream<List<int>> _chunked(List<int> bytes) async* {
  const size = 40;
  for (var offset = 0; offset < bytes.length; offset += size) {
    yield bytes.sublist(
        offset, offset + size > bytes.length ? bytes.length : offset + size);
  }
}

void main() {
  late Directory root;
  late ModelStorage storage;
  final bytes = List<int>.generate(128, (index) => index);
  late final artifact =
      artifactFixture(byteLength: bytes.length, sha256: sha256Of(bytes));

  setUp(() async {
    root = await createModelRoot();
    storage = ModelStorage(rootDirectory: () async => root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('downloads, verifies and installs a fresh artifact', () async {
    final transport = _FakeTransport([
      () => _response(bytes: bytes, etag: '"v1"'),
    ]);
    final progress = <ModelDownloadProgress>[];

    await ModelDownloader(storage: storage, transport: transport).download(
      artifact,
      cancellation: TestCancellation(),
      onProgress: progress.add,
    );

    final installed = await storage.modelFile(artifact.id);
    expect(await installed.readAsBytes(), bytes);
    expect(await (await storage.partialFile(artifact.id)).exists(), isFalse);
    expect(await storage.readPartialMetadata(artifact.id), isNull);
    expect(transport.requests.single.rangeStart, isNull);
    expect(
      progress
          .where((event) => event.phase == ModelDownloadPhase.downloading)
          .last
          .fraction,
      1,
    );
    expect(progress.last.phase, ModelDownloadPhase.verifying);
  });

  test('resumes with a Range request and the stored validator', () async {
    await writePartial(storage, artifact, bytes.sublist(0, 64), etag: '"v1"');
    final transport = _FakeTransport([
      () => _response(
            statusCode: 206,
            bytes: bytes.sublist(64),
            contentRange: 'bytes 64-127/128',
            etag: '"v1"',
          ),
    ]);

    await ModelDownloader(storage: storage, transport: transport)
        .download(artifact, cancellation: TestCancellation());

    expect(transport.requests.single.rangeStart, 64);
    expect(transport.requests.single.ifRange, '"v1"');
    expect(
      await (await storage.modelFile(artifact.id)).readAsBytes(),
      bytes,
    );
  });

  test('resumes with Last-Modified when the range response adds an ETag',
      () async {
    const modified = 'Wed, 21 Oct 2015 07:28:00 GMT';
    await writePartial(storage, artifact, bytes.sublist(0, 64),
        lastModified: modified);
    final transport = _FakeTransport([
      () => _response(
            statusCode: 206,
            bytes: bytes.sublist(64),
            contentRange: 'bytes 64-127/128',
            etag: '"v1"',
            lastModified: modified,
          ),
    ]);

    await ModelDownloader(storage: storage, transport: transport)
        .download(artifact, cancellation: TestCancellation());

    expect(transport.requests, hasLength(1));
    expect(transport.requests.single.ifRange, modified);
    expect(
      await (await storage.modelFile(artifact.id)).readAsBytes(),
      bytes,
    );
  });

  test('restarts when the server ignores the Range request', () async {
    await writePartial(storage, artifact, bytes.sublist(0, 64), etag: '"v1"');
    final transport = _FakeTransport([
      () => _response(bytes: bytes, etag: '"v1"'),
    ]);

    await ModelDownloader(storage: storage, transport: transport)
        .download(artifact, cancellation: TestCancellation());

    expect(transport.requests.single.rangeStart, 64);
    expect(
      await (await storage.modelFile(artifact.id)).readAsBytes(),
      bytes,
    );
  });

  test('retries once from scratch when a resumed artifact changed', () async {
    await writePartial(storage, artifact, bytes.sublist(0, 64), etag: '"old"');
    final changed = bytes.reversed.toList();
    final transport = _FakeTransport([
      () => _response(bytes: changed, etag: '"new"'),
      () => _response(bytes: bytes, etag: '"v1"'),
    ]);

    await ModelDownloader(storage: storage, transport: transport)
        .download(artifact, cancellation: TestCancellation());

    expect(transport.requests, hasLength(2));
    expect(transport.requests.last.rangeStart, isNull);
    expect(
      await (await storage.modelFile(artifact.id)).readAsBytes(),
      bytes,
    );
  });

  test('rejects a corrupt fresh download without promoting it', () async {
    final transport = _FakeTransport([
      () => _response(bytes: bytes.reversed.toList(), etag: '"v1"'),
    ]);

    await expectLater(
      ModelDownloader(storage: storage, transport: transport)
          .download(artifact, cancellation: TestCancellation()),
      throwsA(isA<EngineFailure>().having(
          (error) => error.code, 'code', EngineFailureCode.modelUnavailable)),
    );

    expect(await (await storage.modelFile(artifact.id)).exists(), isFalse);
    expect(await (await storage.partialFile(artifact.id)).exists(), isFalse);
  });

  test('cancellation aborts the body and preserves the partial download',
      () async {
    final body = StreamController<List<int>>();
    var aborted = false;
    final transport = _FakeTransport([
      () => _response(
            bytes: bytes,
            etag: '"v1"',
            body: body.stream,
            abort: () async {
              aborted = true;
              if (!body.isClosed) await body.close();
            },
          ),
    ]);
    final cancellation = TestCancellation();
    body.add(bytes.sublist(0, 40));
    final download =
        ModelDownloader(storage: storage, transport: transport).download(
      artifact,
      cancellation: cancellation,
      onProgress: (progress) {
        if (progress.phase == ModelDownloadPhase.downloading &&
            !cancellation.isCancelled) {
          cancellation.cancel();
        }
      },
    );

    await expectLater(
      download,
      throwsA(isA<EngineFailure>()
          .having((error) => error.code, 'code', EngineFailureCode.cancelled)),
    );

    expect(aborted, isTrue);
    final part = await storage.partialFile(artifact.id);
    expect(await part.exists(), isTrue);
    expect(await part.readAsBytes(), bytes.sublist(0, 40));
    expect(await storage.readPartialMetadata(artifact.id), isNotNull);
    expect(await (await storage.modelFile(artifact.id)).exists(), isFalse);
  });

  test('maps an unusable server response to a typed I/O failure', () async {
    final transport = _FakeTransport([
      () => _response(statusCode: 503, bytes: const []),
    ]);

    await expectLater(
      ModelDownloader(storage: storage, transport: transport)
          .download(artifact, cancellation: TestCancellation()),
      throwsA(isA<EngineFailure>()
          .having((error) => error.code, 'code', EngineFailureCode.ioError)),
    );
  });
}
