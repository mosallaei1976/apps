import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_locale.dart';
import '../application/transcription_job_event.dart';
import '../domain/engine/engine_failure.dart';
import '../domain/engine/engine_types.dart';
import 'transcription_providers.dart';
import 'transcription_session_controller.dart';

class TranscriberScreen extends ConsumerWidget {
  const TranscriberScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLang = ref.watch(localeProvider);
    final session = ref.watch(transcriptionSessionProvider);
    final controller = ref.read(transcriptionSessionProvider.notifier);
    final transcript = session.transcriptText;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppStrings.title(currentLang),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'تغییر زبان / Switch Language',
            icon: const Icon(Icons.language),
            onPressed: () => ref.read(localeProvider.notifier).toggleLanguage(),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // نوار نشان‌دهنده امنیت و حریم خصوصی
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.security, color: Colors.teal, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        AppStrings.subtitle(currentLang),
                        style: const TextStyle(fontSize: 12, color: Colors.tealAccent),
                      ),
                    ),
                  ],
                ),
              ),
              if (session.showsStatus) ...[
                const SizedBox(height: 12),
                _SessionStatus(language: currentLang, session: session),
              ],
              const SizedBox(height: 16),

              // باکس متن خروجی رونویسی
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        transcript.isEmpty
                            ? AppStrings.emptyTranscription(currentLang)
                            : transcript,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.8,
                          color: transcript.isEmpty ? Colors.grey : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // دکمه‌های کپی و پاک‌سازی
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: transcript.isEmpty || session.isActive
                        ? null
                        : controller.clearTranscript,
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: Text(AppStrings.clearText(currentLang)),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: transcript.isEmpty
                        ? null
                        : () {
                            Clipboard.setData(ClipboardData(text: transcript));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  AppStrings.copySuccess(currentLang),
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(AppStrings.copyText(currentLang)),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // کلید ضبط اصلی
              Center(
                child: FloatingActionButton.extended(
                  onPressed: session.isRecording
                      ? () {
                          controller.stopRecording();
                        }
                      : session.isProcessing
                          ? () {
                              controller.cancel();
                            }
                          : () {
                              controller.startRecording(
                                tier: ModelTier.fast,
                              );
                            },
                  backgroundColor:
                      session.isActive ? Colors.redAccent : Colors.teal,
                  icon: Icon(session.isActive ? Icons.stop : Icons.mic),
                  label: Text(
                    session.isRecording
                        ? AppStrings.stopRecording(currentLang)
                        : session.isProcessing
                            ? AppStrings.cancelTranscription(currentLang)
                            : AppStrings.startRecording(currentLang),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionStatus extends StatelessWidget {
  const _SessionStatus({
    required this.language,
    required this.session,
  });

  final AppLanguage language;
  final TranscriptionSessionState session;

  @override
  Widget build(BuildContext context) {
    final failure = session.failure;
    final color = switch (session.phase) {
      TranscriptionPhase.recording => Colors.redAccent,
      TranscriptionPhase.failed => Colors.redAccent,
      TranscriptionPhase.cancelled => Colors.amber,
      TranscriptionPhase.completed => Colors.tealAccent,
      _ => Colors.teal,
    };
    final icon = switch (session.phase) {
      TranscriptionPhase.recording => Icons.mic,
      TranscriptionPhase.failed => Icons.error_outline,
      TranscriptionPhase.cancelled => Icons.cancel_outlined,
      TranscriptionPhase.completed => Icons.check_circle_outline,
      _ => Icons.graphic_eq,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (session.isProcessing)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _statusText(language, session),
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ),
            ],
          ),
          if (failure != null) ...[
            const SizedBox(height: 6),
            Text(
              failure.message,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
          if (session.isProcessing) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: session.progress,
              minHeight: 4,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ],
        ],
      ),
    );
  }
}

String _statusText(
  AppLanguage language,
  TranscriptionSessionState session,
) {
  final failure = session.failure;
  if (failure != null) {
    return switch (failure.code) {
      EngineFailureCode.unsupported => AppStrings.engineUnavailable(language),
      EngineFailureCode.notReady => AppStrings.engineNotReady(language),
      EngineFailureCode.permissionDenied =>
        AppStrings.microphonePermissionDenied(language),
      _ => AppStrings.transcriptionFailed(language),
    };
  }

  return switch (session.phase) {
    TranscriptionPhase.recording => AppStrings.recording(language),
    TranscriptionPhase.completed =>
      AppStrings.transcriptionCompleted(language),
    TranscriptionPhase.cancelled =>
      AppStrings.transcriptionCancelled(language),
    TranscriptionPhase.failed => AppStrings.transcriptionFailed(language),
    _ => switch (session.stage) {
        TranscriptionStage.checkingReadiness =>
          AppStrings.checkingEngine(language),
        TranscriptionStage.resolvingModel => AppStrings.checkingModel(language),
        TranscriptionStage.preparingAudio =>
          AppStrings.preparingAudio(language),
        TranscriptionStage.loadingModel => AppStrings.loadingModel(language),
        TranscriptionStage.transcribing => AppStrings.transcribing(language),
        TranscriptionStage.cleaningUp => AppStrings.cleaningUp(language),
        null => AppStrings.startRecording(language),
      },
  };
}
