import 'dart:async';

import 'package:client/features/transcriber/domain/engine/engine_failure.dart';
import 'package:client/features/transcriber/domain/engine/engine_types.dart';
import 'package:client/features/transcriber/domain/ports/cancellation_signal.dart';
import 'package:client/features/transcriber/domain/ports/model_management.dart';

final class FakeModelRepository implements ModelRepository {
  FakeModelRepository({
    List<ModelProfile>? profiles,
    Map<ModelTier, ModelInstallation?>? installations,
  })  : profiles = profiles ?? <ModelProfile>[],
        installations = installations ?? <ModelTier, ModelInstallation?>{};

  List<ModelProfile> profiles;
  Map<ModelTier, ModelInstallation?> installations;
  final List<ModelTier> deleted = [];
  EngineFailure? listFailure;
  EngineFailure? deleteFailure;
  int listCalls = 0;

  @override
  Future<List<ModelProfile>> listProfiles() async {
    listCalls++;
    final failure = listFailure;
    if (failure != null) throw failure;
    return List.unmodifiable(profiles);
  }

  @override
  Future<ModelInstallation?> installationFor(ModelTier tier) async =>
      installations[tier];

  @override
  Future<void> delete(ModelTier tier) async {
    final failure = deleteFailure;
    if (failure != null) throw failure;
    deleted.add(tier);
    installations[tier] = null;
  }
}

final class FakeModelDownloadCall {
  FakeModelDownloadCall(this.tier, this.cancellation, this.onProgress);

  final ModelTier tier;
  final CancellationSignal cancellation;
  final void Function(ModelDownloadProgress progress)? onProgress;
  final Completer<void> _done = Completer<void>();

  Future<void> get done => _done.future;

  bool get isCancelled => cancellation.isCancelled;

  void progress(
    int receivedBytes, {
    required int totalBytes,
    ModelDownloadStage stage = ModelDownloadStage.downloading,
  }) {
    onProgress?.call(ModelDownloadProgress(
      tier: tier,
      stage: stage,
      receivedBytes: receivedBytes,
      totalBytes: totalBytes,
    ));
  }

  void complete() {
    if (!_done.isCompleted) _done.complete();
  }

  void fail(Object error) {
    if (!_done.isCompleted) _done.completeError(error);
  }
}

final class FakeModelDownloadService implements ModelDownloadService {
  final List<FakeModelDownloadCall> calls = [];
  int disposeCalls = 0;

  @override
  Future<void> download(
    ModelTier tier, {
    required CancellationSignal cancellation,
    void Function(ModelDownloadProgress progress)? onProgress,
  }) {
    final call = FakeModelDownloadCall(tier, cancellation, onProgress);
    calls.add(call);
    return call.done;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}
