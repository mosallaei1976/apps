import 'dart:io';

import 'package:client/features/transcriber/domain/engine/abstract_engine_interface.dart';
import 'package:client/platform/models/model_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/model_fixtures.dart';

void main() {
  late Directory root;
  late ModelStorage storage;
  final bytes = List<int>.generate(256, (index) => index);
  late final artifact =
      artifactFixture(byteLength: bytes.length, sha256: sha256Of(bytes));

  setUp(() async {
    root = await createModelRoot();
    storage = ModelStorage(rootDirectory: () async => root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('verifies an installed artifact with the exact size and digest',
      () async {
    await installBytes(storage, artifact, bytes);

    await storage.verify(artifact, cancellation: TestCancellation());
  });

  test('rejects missing, truncated and modified artifacts', () async {
    final cancellation = TestCancellation();
    await expectLater(
      storage.verify(artifact, cancellation: cancellation),
      throwsA(isA<EngineFailure>().having(
          (error) => error.code, 'code', EngineFailureCode.modelUnavailable)),
    );

    await installBytes(storage, artifact, bytes.sublist(1));
    await expectLater(
      storage.verify(artifact, cancellation: cancellation),
      throwsA(isA<EngineFailure>().having(
          (error) => error.code, 'code', EngineFailureCode.modelUnavailable)),
    );

    final modified = [...bytes];
    modified[0] = modified[0] ^ 0xff;
    await installBytes(storage, artifact, modified);
    await expectLater(
      storage.verify(artifact, cancellation: cancellation),
      throwsA(isA<EngineFailure>().having(
          (error) => error.code, 'code', EngineFailureCode.modelUnavailable)),
    );
  });

  test('observes cancellation during verification', () async {
    await installBytes(storage, artifact, bytes);
    final cancellation = TestCancellation()..cancel();

    await expectLater(
      storage.verify(artifact, cancellation: cancellation),
      throwsA(isA<EngineFailure>()
          .having((error) => error.code, 'code', EngineFailureCode.cancelled)),
    );
  });

  test('verifies and promotes a complete partial download', () async {
    await writePartial(storage, artifact, bytes);

    await storage.install(artifact, cancellation: TestCancellation());

    final installed = await storage.modelFile(artifact.id);
    expect(await installed.readAsBytes(), bytes);
    expect(await (await storage.partialFile(artifact.id)).exists(), isFalse);
    expect(await storage.readPartialMetadata(artifact.id), isNull);
  });

  test('does not replace an installed artifact when promotion fails', () async {
    final original = List<int>.filled(bytes.length, 7);
    await installBytes(storage, artifact, original);
    await writePartial(storage, artifact, bytes.sublist(1));

    await expectLater(
      storage.install(artifact, cancellation: TestCancellation()),
      throwsA(isA<EngineFailure>()),
    );

    final installed = await storage.modelFile(artifact.id);
    expect(await installed.readAsBytes(), original);
  });

  test('deletes installed artifacts and resumable state', () async {
    await installBytes(storage, artifact, bytes);
    await writePartial(storage, artifact, bytes);

    await storage.delete(artifact.id);

    expect(await (await storage.modelFile(artifact.id)).exists(), isFalse);
    expect(await (await storage.partialFile(artifact.id)).exists(), isFalse);
    expect(await storage.readPartialMetadata(artifact.id), isNull);
  });

  test('sweeps only stale download files', () async {
    final oldPart = await storage.partialFile(artifact.id);
    final oldMetadata = await storage.partialMetadataFile(artifact.id);
    await oldPart.writeAsBytes([1, 2, 3]);
    await oldMetadata.writeAsString('{}');
    final old = DateTime.now().subtract(const Duration(days: 8));
    await oldPart.setLastModified(old);
    await oldMetadata.setLastModified(old);

    final recent = await storage.partialFile('recent-model');
    await recent.writeAsBytes([1]);

    final removed = await storage.sweepStaleDownloads();

    expect(removed, 2);
    expect(await oldPart.exists(), isFalse);
    expect(await oldMetadata.exists(), isFalse);
    expect(await recent.exists(), isTrue);
  });
}
