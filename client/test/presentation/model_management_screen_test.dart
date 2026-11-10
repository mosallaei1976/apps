import 'package:client/core/l10n/app_locale.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/features/transcriber/domain/engine/engine_failure.dart';
import 'package:client/features/transcriber/domain/engine/engine_types.dart';
import 'package:client/features/transcriber/domain/ports/model_management.dart';
import 'package:client/features/transcriber/presentation/model_management_providers.dart';
import 'package:client/features/transcriber/presentation/model_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  FakeModelRepository repositoryWith({
    bool fastInstalled = false,
    bool balancedInstalled = false,
  }) =>
      FakeModelRepository(
        profiles: [fast, balanced],
        installations: {
          ModelTier.fast:
              ModelInstallation(profile: fast, installed: fastInstalled),
          ModelTier.balanced: ModelInstallation(
            profile: balanced,
            installed: balancedInstalled,
          ),
        },
      );

  Widget buildScreen({
    required FakeModelRepository repository,
    required FakeModelDownloadService service,
    AppLanguage language = AppLanguage.persian,
  }) {
    return ProviderScope(
      overrides: [
        modelRepositoryProvider.overrideWithValue(repository),
        modelDownloadServiceProvider.overrideWithValue(service),
        localeProvider.overrideWith(
          (ref) => LocaleNotifier()..setLanguage(language),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Directionality(
          textDirection: language.direction,
          child: const ModelManagementScreen(),
        ),
      ),
    );
  }

  testWidgets('renders both profiles with size and explicit download actions',
      (tester) async {
    final repository = repositoryWith();
    final service = FakeModelDownloadService();

    await tester.pumpWidget(
      buildScreen(repository: repository, service: service),
    );
    await tester.pumpAndSettle();

    expect(find.text('مدل سریع'), findsOneWidget);
    expect(find.text('مدل متعادل'), findsOneWidget);
    expect(find.textContaining('~80 MB'), findsOneWidget);
    expect(find.textContaining('~200 MB'), findsOneWidget);
    expect(find.byKey(const ValueKey('model-download-fast')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('model-download-balanced')),
      findsOneWidget,
    );
    expect(service.calls, isEmpty);
  });

  testWidgets('download shows progress, speed and pause, then resumes',
      (tester) async {
    final repository = repositoryWith();
    final service = FakeModelDownloadService();

    await tester.pumpWidget(
      buildScreen(repository: repository, service: service),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('model-download-fast')));
    await tester.pump();
    expect(service.calls, hasLength(1));

    service.calls.single.progress(40000000, totalBytes: fast.byteLength);
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsWidgets);
    expect(find.textContaining('50%'), findsOneWidget);
    expect(find.textContaining('MB/s'), findsOneWidget);
    expect(find.byKey(const ValueKey('model-pause-fast')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('model-pause-fast')));
    await tester.pump();
    service.calls.single.fail(
      const EngineFailure(EngineFailureCode.cancelled, 'Paused by user.'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('model-resume-fast')), findsOneWidget);
    expect(find.textContaining('50%'), findsOneWidget);
  });

  testWidgets('verifying state is shown after the stream completes',
      (tester) async {
    final repository = repositoryWith();
    final service = FakeModelDownloadService();

    await tester.pumpWidget(
      buildScreen(repository: repository, service: service),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('model-download-fast')));
    await tester.pump();
    service.calls.single.progress(
      80000000,
      totalBytes: fast.byteLength,
      stage: ModelDownloadStage.verifying,
    );
    await tester.pump();

    expect(find.text('در حال بررسی SHA-256...'), findsOneWidget);
  });

  testWidgets('a failed download shows an error banner and retry action',
      (tester) async {
    final repository = repositoryWith();
    final service = FakeModelDownloadService();

    await tester.pumpWidget(
      buildScreen(repository: repository, service: service),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('model-download-fast')));
    await tester.pump();
    service.calls.single.progress(1000, totalBytes: fast.byteLength);
    service.calls.single.fail(
      const EngineFailure(EngineFailureCode.ioError, 'Network dropped.'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Network dropped.'), findsOneWidget);
    expect(find.byKey(const ValueKey('model-retry-fast')), findsOneWidget);
  });

  testWidgets('an installed profile offers delete and purges weights',
      (tester) async {
    final repository = repositoryWith(fastInstalled: true);
    final service = FakeModelDownloadService();

    await tester.pumpWidget(
      buildScreen(repository: repository, service: service),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('model-delete-fast')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('model-delete-fast')));
    await tester.pumpAndSettle();

    expect(repository.deleted, [ModelTier.fast]);
    expect(find.byKey(const ValueKey('model-download-fast')), findsOneWidget);
  });

  testWidgets('unsupported platform shows a typed local message',
      (tester) async {
    final repository = repositoryWith()
      ..listFailure = const EngineFailure(
        EngineFailureCode.unsupported,
        'Model downloads are not available in this build.',
      );
    final service = FakeModelDownloadService();

    await tester.pumpWidget(
      buildScreen(repository: repository, service: service),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('دانلود مدل در این نسخه در دسترس نیست.'),
      findsOneWidget,
    );
  });

  testWidgets('English locale renders translated controls', (tester) async {
    final repository = repositoryWith();
    final service = FakeModelDownloadService();

    await tester.pumpWidget(
      buildScreen(
        repository: repository,
        service: service,
        language: AppLanguage.english,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Fast Model'), findsOneWidget);
    expect(find.text('Balanced Model'), findsOneWidget);
    expect(find.text('Download Model'), findsNWidgets(2));
  });
}
