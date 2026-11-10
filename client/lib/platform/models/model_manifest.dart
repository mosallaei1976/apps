import 'dart:convert';

import '../../features/transcriber/domain/engine/engine_types.dart';

/// Whisper model family recorded by a trusted manifest entry.
enum ModelFamily { base, small }

/// Engine build that can consume a manifest artifact.
enum ModelEngine { nativeFfi, wasmWorker }

/// One released, pinned model artifact.
///
/// The manifest is the only source of model identity. Sizes are exact byte
/// lengths and [sha256] is the lowercase hex digest of the complete artifact.
final class ModelArtifact {
  ModelArtifact({
    required String id,
    required this.tier,
    required this.family,
    required this.quantization,
    required String version,
    required this.byteLength,
    required String sha256,
    required this.source,
    required String license,
    required Set<ModelEngine> engines,
  })  : id = _requireArtifactId(id),
        version = _requireText(version, 'version'),
        sha256 = _requireSha256(sha256),
        license = _requireText(license, 'license'),
        engines = Set.unmodifiable(engines) {
    if (byteLength <= 0) {
      throw ArgumentError.value(byteLength, 'byteLength', 'Must be positive');
    }
    if (source.scheme != 'https' || source.host.isEmpty) {
      throw ArgumentError.value(source, 'source', 'Must be an https URL');
    }
    if (this.engines.isEmpty) {
      throw ArgumentError.value(engines, 'engines', 'Must not be empty');
    }
    final expectedFamily =
        tier == ModelTier.fast ? ModelFamily.base : ModelFamily.small;
    if (family != expectedFamily) {
      throw ArgumentError(
          'The ${tier.name} profile must be a ${expectedFamily.name} model.');
    }
  }

  final String id;
  final ModelTier tier;
  final ModelFamily family;
  final ModelQuantization quantization;
  final String version;
  final int byteLength;
  final String sha256;
  final Uri source;
  final String license;
  final Set<ModelEngine> engines;

  ModelSpec toSpec() => ModelSpec(
        id: id,
        tier: tier,
        artifactId: id,
        quantization: quantization,
      );
}

/// Immutable, validated set of released artifacts.
final class ModelManifest {
  ModelManifest(Iterable<ModelArtifact> models)
      : models = List.unmodifiable(models) {
    final ids = <String>{};
    final profiles = <String>{};
    for (final model in this.models) {
      if (!ids.add(model.id)) {
        throw ArgumentError('Duplicate model artifact id: ${model.id}');
      }
      for (final engine in model.engines) {
        if (!profiles.add('${model.tier.name}:${engine.name}')) {
          throw ArgumentError(
              'Duplicate ${model.tier.name} profile for ${engine.name}.');
        }
      }
    }
  }

  static const int schemaVersion = 1;

  final List<ModelArtifact> models;

  ModelArtifact? artifactFor(ModelTier tier, ModelEngine engine) {
    for (final model in models) {
      if (model.tier == tier && model.engines.contains(engine)) {
        return model;
      }
    }
    return null;
  }

  /// Parses and strictly validates a bundled or downloaded manifest.
  ///
  /// Unknown object keys are ignored for forward compatibility, but unknown
  /// enum values, duplicate profiles and invalid artifact metadata are
  /// rejected instead of being guessed.
  factory ModelManifest.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('Invalid model manifest JSON: ${error.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Model manifest must be a JSON object.');
    }
    if (decoded['schemaVersion'] != schemaVersion) {
      throw const FormatException(
          'Unsupported model manifest schemaVersion; expected 1.');
    }
    final entries = decoded['models'];
    if (entries is! List<Object?>) {
      throw const FormatException('Model manifest "models" must be a list.');
    }
    final artifacts = <ModelArtifact>[];
    for (var index = 0; index < entries.length; index++) {
      artifacts.add(_parseArtifact(entries[index], index));
    }
    try {
      return ModelManifest(artifacts);
    } on ArgumentError catch (error) {
      throw FormatException(error.message.toString());
    }
  }
}

ModelArtifact _parseArtifact(Object? raw, int index) {
  final where = 'models[$index]';
  if (raw is! Map<String, Object?>) {
    throw FormatException('$where must be a JSON object.');
  }
  final engines = <ModelEngine>{};
  final rawEngines = raw['engines'];
  if (rawEngines is! List<Object?> || rawEngines.isEmpty) {
    throw FormatException('$where.engines must be a nonempty list.');
  }
  for (final rawEngine in rawEngines) {
    engines.add(_enumValue(ModelEngine.values, rawEngine, '$where.engines'));
  }
  final rawSource = _text(raw, 'source', where);
  final source = Uri.tryParse(rawSource);
  if (source == null) {
    throw FormatException('$where.source must be a URL.');
  }
  try {
    return ModelArtifact(
      id: _text(raw, 'id', where),
      tier: _enumValue(ModelTier.values, raw['tier'], '$where.tier'),
      family: _enumValue(ModelFamily.values, raw['family'], '$where.family'),
      quantization: _quantization(raw['quantization'], '$where.quantization'),
      version: _text(raw, 'version', where),
      byteLength: _integer(raw, 'byteLength', where),
      sha256: _text(raw, 'sha256', where),
      source: source,
      license: _text(raw, 'license', where),
      engines: engines,
    );
  } on ArgumentError catch (error) {
    throw FormatException('$where: ${error.message}');
  }
}

String _text(Map<String, Object?> map, String key, String where) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$where.$key must be a nonempty string.');
  }
  return value;
}

int _integer(Map<String, Object?> map, String key, String where) {
  final value = map[key];
  if (value is! int) {
    throw FormatException('$where.$key must be an integer.');
  }
  return value;
}

T _enumValue<T extends Enum>(List<T> values, Object? raw, String where) {
  if (raw is String) {
    for (final value in values) {
      if (value.name == raw) return value;
    }
  }
  throw FormatException('$where has an unsupported value; expected one of '
      '${values.map((value) => value.name).join(', ')}.');
}

ModelQuantization _quantization(Object? raw, String where) => switch (raw) {
      'q8_0' => ModelQuantization.q8_0,
      'q5_1' => ModelQuantization.q5_1,
      _ => throw FormatException(
          '$where has an unsupported value; expected q8_0 or q5_1.'),
    };

final _artifactIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
final _sha256Pattern = RegExp(r'^[0-9a-fA-F]{64}$');

String _requireArtifactId(String value) {
  if (!_artifactIdPattern.hasMatch(value)) {
    throw ArgumentError.value(value, 'id',
        'Must start with a letter or digit and contain only A-Z, a-z, 0-9, dot, underscore or hyphen');
  }
  return value;
}

String _requireSha256(String value) {
  if (!_sha256Pattern.hasMatch(value)) {
    throw ArgumentError.value(
        value, 'sha256', 'Must be 64 hexadecimal characters');
  }
  return value.toLowerCase();
}

String _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty');
  }
  return value;
}
