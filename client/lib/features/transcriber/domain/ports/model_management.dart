import '../engine/engine_types.dart';
import 'cancellation_signal.dart';

/// A downloadable model profile pinned by the trusted manifest.
///
/// The profile deliberately exposes no remote URL or hash: those details stay
/// inside the platform adapter so presentation and application code cannot
/// construct or redirect a download.
final class ModelProfile {
  ModelProfile({
    required this.tier,
    required this.byteLength,
    required this.quantization,
    required String version,
  }) : version = _requireText(version, 'version') {
    if (byteLength <= 0) {
      throw ArgumentError.value(byteLength, 'byteLength', 'Must be positive');
    }
  }

  final ModelTier tier;
  final int byteLength;
  final ModelQuantization quantization;
  final String version;
}

/// Local state of one profile: installed, partially downloaded or absent.
final class ModelInstallation {
  const ModelInstallation({
    required this.profile,
    required this.installed,
    this.partialBytes = 0,
  });

  final ModelProfile profile;
  final bool installed;

  /// Bytes already present in a resumable `.part` file when not installed.
  final int partialBytes;
}

/// Reads and deletes locally managed model weights.
abstract interface class ModelRepository {
  /// Profiles the trusted manifest releases for this platform, in profile order.
  Future<List<ModelProfile>> listProfiles();

  /// Returns `null` when no released profile exists for [tier].
  Future<ModelInstallation?> installationFor(ModelTier tier);

  /// Deletes installed weights and any resumable partial download.
  Future<void> delete(ModelTier tier);
}

enum ModelDownloadStage { downloading, verifying }

final class ModelDownloadProgress {
  const ModelDownloadProgress({
    required this.tier,
    required this.stage,
    required this.receivedBytes,
    required this.totalBytes,
  });

  final ModelTier tier;
  final ModelDownloadStage stage;
  final int receivedBytes;
  final int totalBytes;

  double get fraction {
    if (totalBytes <= 0) return 0;
    final value = receivedBytes / totalBytes;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }
}

/// Performs one explicit download attempt, resuming an existing `.part` file
/// when present, then verifies SHA-256 before the platform promotes it.
///
/// Cancellation pauses the attempt and preserves resumable state. Calling
/// [download] again resumes from the preserved bytes.
abstract interface class ModelDownloadService {
  Future<void> download(
    ModelTier tier, {
    required CancellationSignal cancellation,
    void Function(ModelDownloadProgress progress)? onProgress,
  });

  Future<void> dispose();
}

String _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty');
  }
  return value;
}
