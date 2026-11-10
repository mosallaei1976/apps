import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:client/features/transcriber/domain/engine/abstract_engine_interface.dart';
import 'package:client/features/transcriber/domain/ports/cancellation_signal.dart';
import 'package:client/platform/models/model_manifest.dart';
import 'package:client/platform/models/model_storage.dart';
import 'package:crypto/crypto.dart';

final class TestCancellation implements CancellationSignal {
  bool _cancelled = false;
  final _cancelledSignal = Completer<void>();

  @override
  bool get isCancelled => _cancelled;

  @override
  Future<void> get whenCancelled => _cancelledSignal.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancelledSignal.complete();
  }

  @override
  void throwIfCancelled() {
    if (_cancelled) {
      throw const EngineFailure(
          EngineFailureCode.cancelled, 'Job was cancelled.');
    }
  }
}

String sha256Of(List<int> bytes) => sha256.convert(bytes).toString();

ModelArtifact artifactFixture({
  String id = 'whisper-base-q5',
  ModelTier tier = ModelTier.fast,
  ModelFamily? family,
  ModelQuantization quantization = ModelQuantization.q5_1,
  String version = '1.0.0',
  required int byteLength,
  required String sha256,
  String source = 'https://models.example.invalid/whisper-base-q5.bin',
  String license = 'MIT',
  Set<ModelEngine> engines = const {ModelEngine.nativeFfi},
}) =>
    ModelArtifact(
      id: id,
      tier: tier,
      family: family ??
          (tier == ModelTier.fast ? ModelFamily.base : ModelFamily.small),
      quantization: quantization,
      version: version,
      byteLength: byteLength,
      sha256: sha256,
      source: Uri.parse(source),
      license: license,
      engines: engines,
    );

Map<String, Object?> artifactJson(ModelArtifact artifact) => {
      'id': artifact.id,
      'tier': artifact.tier.name,
      'family': artifact.family.name,
      'quantization': switch (artifact.quantization) {
        ModelQuantization.q8_0 => 'q8_0',
        ModelQuantization.q5_1 => 'q5_1',
      },
      'version': artifact.version,
      'byteLength': artifact.byteLength,
      'sha256': artifact.sha256,
      'source': artifact.source.toString(),
      'license': artifact.license,
      'engines': artifact.engines.map((engine) => engine.name).toList(),
    };

String manifestJson(List<ModelArtifact> artifacts) => jsonEncode({
      'schemaVersion': ModelManifest.schemaVersion,
      'models': artifacts.map(artifactJson).toList(),
    });

Future<Directory> createModelRoot() =>
    Directory.systemTemp.createTemp('persian-transcriber-model-test-');

Future<void> installBytes(
  ModelStorage storage,
  ModelArtifact artifact,
  List<int> bytes,
) async {
  final file = await storage.modelFile(artifact.id);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
}

Future<void> writePartial(
  ModelStorage storage,
  ModelArtifact artifact,
  List<int> bytes, {
  String? etag,
  String? lastModified,
}) async {
  final part = await storage.partialFile(artifact.id);
  await part.writeAsBytes(bytes, flush: true);
  await storage.writePartialMetadata(artifact.id, {
    'artifactId': artifact.id,
    'version': artifact.version,
    'sha256': artifact.sha256,
    'byteLength': artifact.byteLength,
    'source': artifact.source.toString(),
    if (etag != null) 'etag': etag,
    if (lastModified != null) 'lastModified': lastModified,
  });
}
