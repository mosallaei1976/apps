import '../../features/transcriber/domain/engine/engine_failure.dart';
import '../../features/transcriber/domain/engine/engine_types.dart';
import '../../features/transcriber/domain/ports/cancellation_signal.dart';
import '../../features/transcriber/domain/ports/model_management.dart';
import 'local_verified_model_access.dart' show ModelManifestLoader;
import 'model_download.dart' as downloader;
import 'model_manifest.dart';
import 'model_storage.dart';

/// Native [ModelRepository] backed by the trusted manifest and local storage.
final class LocalModelRepository implements ModelRepository {
  LocalModelRepository({
    required ModelManifestLoader manifestLoader,
    required ModelStorage storage,
    required ModelEngine engine,
  })  : _catalog = _ManifestCatalog(manifestLoader),
        _storage = storage,
        _engine = engine;

  final _ManifestCatalog _catalog;
  final ModelStorage _storage;
  final ModelEngine _engine;

  @override
  Future<List<ModelProfile>> listProfiles() async {
    final manifest = await _catalog.load();
    final profiles = <ModelProfile>[];
    for (final tier in ModelTier.values) {
      final artifact = manifest.artifactFor(tier, _engine);
      if (artifact != null) profiles.add(_profile(artifact));
    }
    return List.unmodifiable(profiles);
  }

  @override
  Future<ModelInstallation?> installationFor(ModelTier tier) async {
    final artifact = (await _catalog.load()).artifactFor(tier, _engine);
    if (artifact == null) return null;
    final model = await _storage.modelFile(artifact.id);
    // A cheap existence/size check is enough for the settings status. The
    // complete SHA-256 is re-verified after every download and again by
    // LocalVerifiedModelAccess before an engine may load the artifact.
    final installed = await model.exists() &&
        await model.length() == artifact.byteLength;
    var partialBytes = 0;
    if (!installed) {
      final part = await _storage.partialFile(artifact.id);
      if (await part.exists()) partialBytes = await part.length();
    }
    return ModelInstallation(
      profile: _profile(artifact),
      installed: installed,
      partialBytes: partialBytes,
    );
  }

  @override
  Future<void> delete(ModelTier tier) async {
    final artifact = (await _catalog.load()).artifactFor(tier, _engine);
    if (artifact == null) {
      throw EngineFailure(
        EngineFailureCode.modelUnavailable,
        'No released ${tier.name} model profile is configured for this platform.',
      );
    }
    await _storage.delete(artifact.id);
  }

  ModelProfile _profile(ModelArtifact artifact) => ModelProfile(
        tier: artifact.tier,
        byteLength: artifact.byteLength,
        quantization: artifact.quantization,
        version: artifact.version,
      );
}

/// Native [ModelDownloadService] that resumes and verifies through
/// [ModelDownloader].
final class LocalModelDownloadService implements ModelDownloadService {
  LocalModelDownloadService({
    required ModelManifestLoader manifestLoader,
    required ModelStorage storage,
    required downloader.ModelDownloadTransport transport,
    required ModelEngine engine,
  })  : _catalog = _ManifestCatalog(manifestLoader),
        _storage = storage,
        _transport = transport,
        _engine = engine;

  final _ManifestCatalog _catalog;
  final ModelStorage _storage;
  final downloader.ModelDownloadTransport _transport;
  final ModelEngine _engine;
  downloader.ModelDownloader? _downloader;

  @override
  Future<void> download(
    ModelTier tier, {
    required CancellationSignal cancellation,
    void Function(ModelDownloadProgress progress)? onProgress,
  }) async {
    cancellation.throwIfCancelled();
    final artifact = (await _catalog.load()).artifactFor(tier, _engine);
    if (artifact == null) {
      throw EngineFailure(
        EngineFailureCode.modelUnavailable,
        'No released ${tier.name} model profile is configured for this platform.',
      );
    }
    final runner = _downloader ??=
        downloader.ModelDownloader(storage: _storage, transport: _transport);
    await runner.download(
      artifact,
      cancellation: cancellation,
      onProgress: onProgress == null
          ? null
          : (progress) {
              onProgress(ModelDownloadProgress(
                tier: tier,
                stage: progress.phase == downloader.ModelDownloadPhase.verifying
                    ? ModelDownloadStage.verifying
                    : ModelDownloadStage.downloading,
                receivedBytes: progress.receivedBytes,
                totalBytes: progress.totalBytes,
              ));
            },
    );
  }

  @override
  Future<void> dispose() => _transport.close();
}

/// Loads and caches the trusted manifest, failing closed with a typed error.
final class _ManifestCatalog {
  _ManifestCatalog(this._loader);

  final ModelManifestLoader _loader;
  Future<ModelManifest>? _pending;

  Future<ModelManifest> load() async {
    final pending = _pending ??= _loadNow();
    try {
      return await pending;
    } catch (_) {
      if (identical(_pending, pending)) _pending = null;
      rethrow;
    }
  }

  Future<ModelManifest> _loadNow() async {
    try {
      return await _loader();
    } on EngineFailure {
      rethrow;
    } on Object {
      throw const EngineFailure(
        EngineFailureCode.modelUnavailable,
        'The trusted model manifest is unavailable or invalid.',
      );
    }
  }
}
