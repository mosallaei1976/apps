import '../domain/engine/engine_failure.dart';
import '../domain/engine/engine_types.dart';
import '../domain/ports/model_management.dart';

/// Typed state of one model profile download.
sealed class ModelDownloadStatus {
  const ModelDownloadStatus();
}

final class ModelNotDownloaded extends ModelDownloadStatus {
  const ModelNotDownloaded({this.partialBytes = 0});

  final int partialBytes;
}

final class ModelDownloading extends ModelDownloadStatus {
  const ModelDownloading({
    required this.progress,
    required this.receivedBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
  });

  final double progress;
  final int receivedBytes;
  final int totalBytes;
  final double bytesPerSecond;
}

final class ModelVerifyingSha256 extends ModelDownloadStatus {
  const ModelVerifyingSha256({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int totalBytes;
}

final class ModelDownloadPaused extends ModelDownloadStatus {
  const ModelDownloadPaused({
    required this.receivedBytes,
    required this.totalBytes,
  });

  final int receivedBytes;
  final int totalBytes;

  double get progress {
    if (totalBytes <= 0) return 0;
    final value = receivedBytes / totalBytes;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }
}

final class ModelReady extends ModelDownloadStatus {
  const ModelReady();
}

final class ModelDownloadError extends ModelDownloadStatus {
  const ModelDownloadError({
    required this.failure,
    required this.receivedBytes,
    required this.totalBytes,
  });

  final EngineFailure failure;
  final int receivedBytes;
  final int totalBytes;

  bool get canResume => receivedBytes > 0;
}

/// No released artifact is configured for this profile on this platform.
final class ModelProfileUnavailable extends ModelDownloadStatus {
  const ModelProfileUnavailable(this.reason);

  final String reason;
}

final class ModelProfileState {
  const ModelProfileState({required this.profile, required this.status});

  final ModelProfile profile;
  final ModelDownloadStatus status;

  ModelProfileState copyWith({ModelDownloadStatus? status}) =>
      ModelProfileState(profile: profile, status: status ?? this.status);
}

final class ModelManagementState {
  const ModelManagementState({
    this.isSupported = true,
    this.isLoading = false,
    this.profiles = const [],
    this.failure,
  });

  final bool isSupported;
  final bool isLoading;
  final List<ModelProfileState> profiles;

  /// A load-level failure, such as an invalid manifest or an unsupported build.
  final EngineFailure? failure;

  ModelProfileState? profileFor(ModelTier tier) {
    for (final entry in profiles) {
      if (entry.profile.tier == tier) return entry;
    }
    return null;
  }
}
