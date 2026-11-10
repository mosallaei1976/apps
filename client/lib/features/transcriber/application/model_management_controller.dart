import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/engine/engine_failure.dart';
import '../domain/engine/engine_types.dart';
import '../domain/ports/cancellation_signal.dart';
import '../domain/ports/model_management.dart';
import 'model_management_state.dart';

/// Owns explicit, user-triggered model downloads and their typed UI state.
///
/// The controller never starts a download on its own. [initialize] only reads
/// local installation state so the UI can render the correct action.
final class ModelManagementController
    extends StateNotifier<ModelManagementState> {
  ModelManagementController({
    required ModelRepository repository,
    required ModelDownloadService downloadService,
    DateTime Function()? clock,
  })  : _repository = repository,
        _downloadService = downloadService,
        _clock = clock ?? DateTime.now,
        super(const ModelManagementState(isLoading: true));

  final ModelRepository _repository;
  final ModelDownloadService _downloadService;
  final DateTime Function() _clock;

  final Map<ModelTier, _DownloadRun> _runs = {};
  final Map<ModelTier, _SpeedSample> _samples = {};
  final Map<ModelTier, int> _received = {};

  Future<void> initialize() async {
    if (!mounted) return;
    state = ModelManagementState(
      isSupported: state.isSupported,
      isLoading: true,
      profiles: state.profiles,
      failure: state.failure,
    );
    try {
      final profiles = await _repository.listProfiles();
      if (!mounted) return;
      final entries = <ModelProfileState>[];
      for (final profile in profiles) {
        final installation = await _repository.installationFor(profile.tier);
        if (!mounted) return;
        entries.add(ModelProfileState(
          profile: profile,
          status: _statusFor(installation),
        ));
      }
      state = ModelManagementState(profiles: entries);
    } on EngineFailure catch (failure) {
      if (!mounted) return;
      state = ModelManagementState(
        isSupported: failure.code != EngineFailureCode.unsupported,
        failure: failure,
      );
    } on Object {
      if (!mounted) return;
      state = const ModelManagementState(
        failure: EngineFailure(
          EngineFailureCode.unknown,
          'Could not read the local model state.',
        ),
      );
    }
  }

  ModelDownloadStatus _statusFor(ModelInstallation? installation) {
    if (installation == null) {
      return const ModelProfileUnavailable(
        'No released model profile is configured for this platform.',
      );
    }
    if (installation.installed) return const ModelReady();
    if (installation.partialBytes > 0) {
      return ModelDownloadPaused(
        receivedBytes: installation.partialBytes,
        totalBytes: installation.profile.byteLength,
      );
    }
    return const ModelNotDownloaded();
  }

  /// Starts a fresh download or resumes a paused one for [tier].
  Future<void> download(ModelTier tier) async {
    if (_runs.containsKey(tier)) return;
    final entry = state.profileFor(tier);
    if (entry == null) return;
    final total = entry.profile.byteLength;
    final cancellation = _ModelCancellation();
    final run = _DownloadRun(cancellation);
    _runs[tier] = run;
    final initialReceived = switch (entry.status) {
      ModelDownloadPaused(:final receivedBytes) => receivedBytes,
      ModelDownloadError(:final receivedBytes) => receivedBytes,
      _ => 0,
    };
    _received[tier] = initialReceived;
    _samples[tier] = _SpeedSample(_clock(), initialReceived);
    _updateStatus(
      tier,
      ModelDownloading(
        progress: total == 0 ? 0 : initialReceived / total,
        receivedBytes: initialReceived,
        totalBytes: total,
        bytesPerSecond: 0,
      ),
    );
    try {
      await _downloadService.download(
        tier,
        cancellation: cancellation,
        onProgress: (progress) => _handleProgress(tier, progress),
      );
      // A completed attempt means verification and atomic promotion succeeded,
      // even if a late pause request arrived after the final rename.
      _received[tier] = total;
      _samples.remove(tier);
      _updateStatus(tier, const ModelReady());
    } on EngineFailure catch (failure) {
      if (failure.code == EngineFailureCode.cancelled ||
          cancellation.isCancelled) {
        _markPaused(tier, total);
      } else {
        _updateStatus(
          tier,
          ModelDownloadError(
            failure: failure,
            receivedBytes: _receivedFor(tier),
            totalBytes: total,
          ),
        );
      }
    } on Object {
      if (cancellation.isCancelled) {
        _markPaused(tier, total);
      } else {
        _updateStatus(
          tier,
          ModelDownloadError(
            failure: const EngineFailure(
              EngineFailureCode.unknown,
              'The model download failed.',
            ),
            receivedBytes: _receivedFor(tier),
            totalBytes: total,
          ),
        );
      }
    } finally {
      _runs.remove(tier);
      run.complete();
    }
  }

  /// Cancels the active attempt, preserving the resumable `.part` file.
  Future<void> pause(ModelTier tier) async {
    final run = _runs[tier];
    if (run == null) return;
    run.cancellation.cancel();
    await run.done.future;
  }

  Future<void> resume(ModelTier tier) => download(tier);

  /// Removes installed weights and any partial download for [tier].
  Future<void> delete(ModelTier tier) async {
    if (_runs.containsKey(tier)) return;
    final total = state.profileFor(tier)?.profile.byteLength ?? 0;
    try {
      await _repository.delete(tier);
      _received.remove(tier);
      _samples.remove(tier);
      _updateStatus(tier, const ModelNotDownloaded());
    } on EngineFailure catch (failure) {
      _updateStatus(
        tier,
        ModelDownloadError(
          failure: failure,
          receivedBytes: 0,
          totalBytes: total,
        ),
      );
    }
  }

  void _handleProgress(ModelTier tier, ModelDownloadProgress progress) {
    if (!mounted) return;
    if (progress.stage == ModelDownloadStage.verifying) {
      _received[tier] = progress.totalBytes;
      _updateStatus(
        tier,
        ModelVerifyingSha256(
          receivedBytes: progress.receivedBytes,
          totalBytes: progress.totalBytes,
        ),
      );
      return;
    }

    _received[tier] = progress.receivedBytes;
    final now = _clock();
    final previous = _samples[tier];
    var bytesPerSecond = 0.0;
    if (previous != null) {
      final elapsedSeconds =
          now.difference(previous.time).inMicroseconds / 1000000.0;
      final deltaBytes = progress.receivedBytes - previous.bytes;
      if (elapsedSeconds > 0 && deltaBytes >= 0) {
        bytesPerSecond = deltaBytes / elapsedSeconds;
      }
    }
    _samples[tier] = _SpeedSample(now, progress.receivedBytes);
    _updateStatus(
      tier,
      ModelDownloading(
        progress: progress.fraction,
        receivedBytes: progress.receivedBytes,
        totalBytes: progress.totalBytes,
        bytesPerSecond: bytesPerSecond,
      ),
    );
  }

  void _markPaused(ModelTier tier, int total) {
    _samples.remove(tier);
    _updateStatus(
      tier,
      ModelDownloadPaused(
        receivedBytes: _receivedFor(tier),
        totalBytes: total,
      ),
    );
  }

  int _receivedFor(ModelTier tier) => _received[tier] ?? 0;

  void _updateStatus(ModelTier tier, ModelDownloadStatus status) {
    if (!mounted) return;
    final profiles = [
      for (final entry in state.profiles)
        entry.profile.tier == tier ? entry.copyWith(status: status) : entry,
    ];
    state = ModelManagementState(
      isSupported: state.isSupported,
      isLoading: state.isLoading,
      profiles: profiles,
      failure: state.failure,
    );
  }

  @override
  void dispose() {
    for (final run in _runs.values) {
      run.cancellation.cancel();
    }
    _runs.clear();
    super.dispose();
  }
}

final class _DownloadRun {
  _DownloadRun(this.cancellation);

  final _ModelCancellation cancellation;
  final Completer<void> done = Completer<void>();

  void complete() {
    if (!done.isCompleted) done.complete();
  }
}

final class _SpeedSample {
  const _SpeedSample(this.time, this.bytes);

  final DateTime time;
  final int bytes;
}

final class _ModelCancellation implements CancellationSignal {
  bool _cancelled = false;
  final Completer<void> _signal = Completer<void>();

  @override
  bool get isCancelled => _cancelled;

  @override
  Future<void> get whenCancelled => _signal.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _signal.complete();
  }

  @override
  void throwIfCancelled() {
    if (_cancelled) {
      throw const EngineFailure(
        EngineFailureCode.cancelled,
        'Model download paused.',
      );
    }
  }
}
