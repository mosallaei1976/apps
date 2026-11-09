import '../../features/transcriber/domain/engine/abstract_engine_interface.dart';
import '../../features/transcriber/domain/ports/cancellation_signal.dart';
import '../../features/transcriber/domain/ports/verified_model_access.dart';
import 'model_manifest.dart';
import 'model_storage.dart';

typedef ModelManifestLoader = Future<ModelManifest> Function();

/// Resolves a model tier only when the trusted manifest pins a compatible
/// artifact and the installed file matches its exact size and SHA-256.
final class LocalVerifiedModelAccess implements VerifiedModelAccess {
  LocalVerifiedModelAccess({
    required ModelManifestLoader manifestLoader,
    required ModelStorage storage,
    required ModelEngine engine,
  })  : _manifestLoader = manifestLoader,
        _storage = storage,
        _engine = engine;

  final ModelManifestLoader _manifestLoader;
  final ModelStorage _storage;
  final ModelEngine _engine;
  Future<ModelManifest>? _manifest;

  @override
  Future<ModelSpec> resolveVerified(
    ModelTier tier, {
    required CancellationSignal cancellation,
  }) async {
    cancellation.throwIfCancelled();
    final manifest = await _loadManifest();
    cancellation.throwIfCancelled();
    final artifact = manifest.artifactFor(tier, _engine);
    if (artifact == null) {
      throw EngineFailure(EngineFailureCode.modelUnavailable,
          'No released ${tier.name} model profile is configured for this platform.');
    }
    await _storage.verify(artifact, cancellation: cancellation);
    cancellation.throwIfCancelled();
    return artifact.toSpec();
  }

  Future<ModelManifest> _loadManifest() async {
    final pending = _manifest ??= _loadManifestNow();
    try {
      return await pending;
    } catch (_) {
      if (identical(_manifest, pending)) _manifest = null;
      rethrow;
    }
  }

  Future<ModelManifest> _loadManifestNow() async {
    try {
      return await _manifestLoader();
    } on EngineFailure {
      rethrow;
    } on Object {
      throw const EngineFailure(EngineFailureCode.modelUnavailable,
          'The trusted model manifest is unavailable or invalid.');
    }
  }
}
