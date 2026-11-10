import 'package:client/features/transcriber/application/model_management_controller.dart';
import 'package:client/features/transcriber/application/model_management_state.dart';
import 'package:client/features/transcriber/domain/engine/engine_failure.dart';
import 'package:client/features/transcriber/domain/engine/engine_types.dart';
import 'package:client/features/transcriber/domain/ports/model_management.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_model_management.dart';

void main() {
  final fast = ModelProfile(
    tier: ModelTier.fast,
    byteLength: 80000000,
    quantization: ModelQuantization.q5K,
    version: '1.0.0',
  );
  final balanced = ModelProfile(
    tier: ModelTier.balanced,
    byteLength: 200000000,
    quantization: ModelQuantization.q5K,
    version: '1.0.0',
  );

  late FakeModelRepository repository;
  late FakeModelDownloadService service;
  late DateTime now;
  late ModelManagementController controller;

  setUp(() {
    repository = FakeModelRepository(profiles: [fast, balanced]);
    service = FakeModelDownloadService();
    now = DateTime(2026, 1, 1);
    controller = ModelManagementController(
      repository: repository,
      downloadService: service,
      clock: () => now,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  ModelDownloadStatus statusFor(ModelTier tier) =>
      controller.state.profileFor(tier)!.status;

  test('initialize maps installed, partial and absent profiles', () async {
    repository.installations = {
      ModelTier.fast: ModelInstallation(profile: fast, installed: true),
      ModelTier.balanced: ModelInstallation(
        profile: balanced,
        installed: false,
        partialBytes: 5000,
      ),
    };

    await controller.initialize();

    expect(controller.state.isLoading, isFalse);
    expect(controller.state.isSupported, isTrue);
    expect(statusFor(ModelTier.fast), isA<ModelReady>());
    final paused = statusFor(ModelTier.balanced) as ModelDownloadPaused;
    expect(paused.receivedBytes, 5000);
    expect(paused.totalBytes, 200000000);
  });

  test('initialize reports an absent profile as not downloaded', () async {
    repository.installations = {
      ModelTier.fast: ModelInstallation(profile: fast, installed: false),
    };

    await controller.initialize();

    expect(statusFor(ModelTier.fast), isA<ModelNotDownloaded>());
  });

  test('initialize never starts a download', () async {
    await controller.initialize();

    expect(repository.listCalls, 1);
    expect(service.calls, isEmpty);
  });

  test('initialize surfaces an unsupported platform as typed state', () async {
    repository.listFailure = const EngineFailure(
      EngineFailureCode.unsupported,
      'Model downloads are not available in this build.',
    );

    await controller.initialize();

    expect(controller.state.isSupported, isFalse);
    expect(controller.state.failure?.code, EngineFailureCode.unsupported);
    expect(controller.state.profiles, isEmpty);
  });

  test('download transitions downloading -> verifying -> ready', () async {
    await controller.initialize();

    final future = controller.download(ModelTier.fast);
    expect(service.calls, hasLength(1));
    expect(service.calls.single.tier, ModelTier.fast);
    expect(statusFor(ModelTier.fast), isA<ModelDownloading>());

    now = now.add(const Duration(seconds: 1));
    service.calls.single.progress(10000000, totalBytes: fast.byteLength);

    final downloading = statusFor(ModelTier.fast) as ModelDownloading;
    expect(downloading.progress, closeTo(0.125, 1e-9));
    expect(downloading.bytesPerSecond, closeTo(10000000, 1));

    service.calls.single.progress(
      80000000,
      totalBytes: fast.byteLength,
      stage: ModelDownloadStage.verifying,
    );
    expect(statusFor(ModelTier.fast), isA<ModelVerifyingSha256>());

    service.calls.single.complete();
    await future;

    expect(statusFor(ModelTier.fast), isA<ModelReady>());
  });

  test('pause cancels the attempt and preserves progress', () async {
    await controller.initialize();
    final future = controller.download(ModelTier.fast);
    service.calls.single.progress(20000000, totalBytes: fast.byteLength);

    final pause = controller.pause(ModelTier.fast);
    expect(service.calls.single.isCancelled, isTrue);
    service.calls.single.fail(
      const EngineFailure(EngineFailureCode.cancelled, 'Paused by user.'),
    );
    await pause;
    await future;

    final paused = statusFor(ModelTier.fast) as ModelDownloadPaused;
    expect(paused.receivedBytes, 20000000);
    expect(paused.progress, closeTo(0.25, 1e-9));
  });

  test('resume starts a second attempt and reaches ready', () async {
    await controller.initialize();
    final first = controller.download(ModelTier.fast);
    service.calls.single.progress(20000000, totalBytes: fast.byteLength);
    final pause = controller.pause(ModelTier.fast);
    service.calls.single.fail(
      const EngineFailure(EngineFailureCode.cancelled, 'Paused by user.'),
    );
    await pause;
    await first;

    final resume = controller.resume(ModelTier.fast);
    expect(service.calls, hasLength(2));
    service.calls[1].progress(
      80000000,
      totalBytes: fast.byteLength,
      stage: ModelDownloadStage.verifying,
    );
    service.calls[1].complete();
    await resume;

    expect(statusFor(ModelTier.fast), isA<ModelReady>());
  });

  test('a non-cancellation failure becomes a resumable error', () async {
    await controller.initialize();
    final future = controller.download(ModelTier.fast);
    service.calls.single.progress(1000, totalBytes: fast.byteLength);
    service.calls.single.fail(
      const EngineFailure(EngineFailureCode.ioError, 'Network dropped.'),
    );
    await future;

    final error = statusFor(ModelTier.fast) as ModelDownloadError;
    expect(error.failure.code, EngineFailureCode.ioError);
    expect(error.canResume, isTrue);
    expect(error.receivedBytes, 1000);
  });

  test('a failure before any bytes is not resumable', () async {
    await controller.initialize();
    final future = controller.download(ModelTier.fast);
    service.calls.single.fail(
      const EngineFailure(EngineFailureCode.ioError, 'Network dropped.'),
    );
    await future;

    final error = statusFor(ModelTier.fast) as ModelDownloadError;
    expect(error.canResume, isFalse);
  });

  test('duplicate download requests share one attempt', () async {
    await controller.initialize();
    final first = controller.download(ModelTier.fast);
    final second = controller.download(ModelTier.fast);

    expect(service.calls, hasLength(1));
    service.calls.single.complete();
    await Future.wait([first, second]);
    expect(statusFor(ModelTier.fast), isA<ModelReady>());
  });

  test('delete removes weights and returns to not downloaded', () async {
    repository.installations = {
      ModelTier.fast: ModelInstallation(profile: fast, installed: true),
    };
    await controller.initialize();
    expect(statusFor(ModelTier.fast), isA<ModelReady>());

    await controller.delete(ModelTier.fast);

    expect(repository.deleted, [ModelTier.fast]);
    expect(statusFor(ModelTier.fast), isA<ModelNotDownloaded>());
  });

  test('delete failure is surfaced as an error state', () async {
    await controller.initialize();
    repository.deleteFailure = const EngineFailure(
      EngineFailureCode.ioError,
      'Could not delete the model artifact.',
    );

    await controller.delete(ModelTier.fast);

    final error = statusFor(ModelTier.fast) as ModelDownloadError;
    expect(error.failure.code, EngineFailureCode.ioError);
  });
}
