import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_locale.dart';
import '../application/model_management_controller.dart';
import '../application/model_management_state.dart';
import '../domain/engine/engine_types.dart';
import 'model_management_providers.dart';

class ModelManagementScreen extends ConsumerStatefulWidget {
  const ModelManagementScreen({super.key});

  @override
  ConsumerState<ModelManagementScreen> createState() =>
      _ModelManagementScreenState();
}

class _ModelManagementScreenState extends ConsumerState<ModelManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(modelManagementProvider.notifier).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(localeProvider);
    final state = ref.watch(modelManagementProvider);
    final controller = ref.read(modelManagementProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.modelManagementTitle(language)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              AppStrings.modelManagementIntro(language),
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
            if (state.isLoading) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator()),
            ],
            if (state.failure != null) ...[
              const SizedBox(height: 16),
              _FailureBanner(
                message: state.isSupported
                    ? state.failure!.message
                    : AppStrings.modelManagementUnavailable(language),
              ),
            ],
            const SizedBox(height: 16),
            for (final entry in state.profiles) ...[
              _ModelCard(
                language: language,
                entry: entry,
                onDownload: () => controller.download(entry.profile.tier),
                onPause: () => controller.pause(entry.profile.tier),
                onResume: () => controller.resume(entry.profile.tier),
                onDelete: () => _delete(controller, entry.profile.tier),
              ),
              const SizedBox(height: 12),
            ],
            if (!state.isLoading &&
                state.failure == null &&
                state.profiles.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(
                  AppStrings.modelUnavailable(language),
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(
    ModelManagementController controller,
    ModelTier tier,
  ) async {
    await controller.delete(tier);
    if (!mounted) return;
    final state = ref.read(modelManagementProvider);
    final entry = state.profileFor(tier);
    if (entry != null && entry.status is ModelNotDownloaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.modelDeleteSuccess(ref.read(localeProvider)),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.language,
    required this.entry,
    required this.onDownload,
    required this.onPause,
    required this.onResume,
    required this.onDelete,
  });

  final AppLanguage language;
  final ModelProfileState entry;
  final VoidCallback onDownload;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onDelete;

  ModelTier get _tier => entry.profile.tier;

  @override
  Widget build(BuildContext context) {
    final isFast = _tier == ModelTier.fast;
    final title = isFast
        ? AppStrings.fastModel(language)
        : AppStrings.balancedModel(language);
    final description = isFast
        ? AppStrings.fastModelDescription(language)
        : AppStrings.balancedModelDescription(language);

    return Card(
      key: ValueKey('model-card-${_tier.name}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isFast ? Icons.bolt : Icons.balance,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${AppStrings.approximateSize(entry.profile.byteLength)}'
              ' · ${_quantizationLabel(entry.profile.quantization)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ..._status(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _status(BuildContext context) {
    final status = entry.status;
    return switch (status) {
      ModelNotDownloaded() => [
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.modelNotDownloaded(language),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              FilledButton.icon(
                key: ValueKey('model-download-${_tier.name}'),
                onPressed: onDownload,
                icon: const Icon(Icons.download, size: 18),
                label: Text(AppStrings.downloadModel(language)),
              ),
            ],
          ),
        ],
      ModelDownloading(
        :final progress,
        :final bytesPerSecond,
      ) =>
        [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${AppStrings.modelDownloading(language)} '
                  '${AppStrings.progressPercent(progress)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Text(
                AppStrings.downloadSpeed(bytesPerSecond),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: OutlinedButton.icon(
              key: ValueKey('model-pause-${_tier.name}'),
              onPressed: onPause,
              icon: const Icon(Icons.pause, size: 18),
              label: Text(AppStrings.pauseDownload(language)),
            ),
          ),
        ],
      ModelVerifyingSha256() => [
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(
            AppStrings.modelVerifying(language),
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ModelDownloadPaused(:final progress) => [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${AppStrings.modelPaused(language)} '
                  '${AppStrings.progressPercent(progress)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              FilledButton.tonalIcon(
                key: ValueKey('model-resume-${_tier.name}'),
                onPressed: onResume,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(AppStrings.resumeDownload(language)),
              ),
            ],
          ),
        ],
      ModelReady() => [
          Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.teal, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppStrings.modelReady(language),
                  style:
                      const TextStyle(fontSize: 13, color: Colors.tealAccent),
                ),
              ),
              OutlinedButton.icon(
                key: ValueKey('model-delete-${_tier.name}'),
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(AppStrings.deleteModel(language)),
              ),
            ],
          ),
        ],
      ModelDownloadError(:final failure, :final canResume) => [
          _FailureBanner(message: failure.message),
          const SizedBox(height: 10),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.tonalIcon(
              key: ValueKey('model-retry-${_tier.name}'),
              onPressed: canResume ? onResume : onDownload,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(
                canResume
                    ? AppStrings.resumeDownload(language)
                    : AppStrings.retryDownload(language),
              ),
            ),
          ),
        ],
      ModelProfileUnavailable() => [
          Text(
            AppStrings.modelUnavailable(language),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
    };
  }

  static String _quantizationLabel(ModelQuantization quantization) =>
      switch (quantization) {
        ModelQuantization.q8_0 => 'Q8_0',
        ModelQuantization.q5_1 => 'Q5_1',
      };
}

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: colors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
