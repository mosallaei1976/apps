import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_locale.dart';

class TranscriberScreen extends ConsumerStatefulWidget {
  const TranscriberScreen({super.key});

  @override
  ConsumerState<TranscriberScreen> createState() => _TranscriberScreenState();
}

class _TranscriberScreenState extends ConsumerState<TranscriberScreen> {
  bool _isRecording = false;
  String _transcribedText = "";

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
      if (_isRecording) {
        _transcribedText = "در حال ضبط و پردازش آفلاین در حافظه موقت (RAM)...";
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentLang = ref.watch(localeProvider);

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
              const SizedBox(height: 16),

              // باکس متن خروجی رونویسی
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _transcribedText.isEmpty
                            ? AppStrings.emptyTranscription(currentLang)
                            : _transcribedText,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.8,
                          color: _transcribedText.isEmpty ? Colors.grey : Colors.white,
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
                    onPressed: _transcribedText.isEmpty
                        ? null
                        : () => setState(() => _transcribedText = ""),
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: Text(AppStrings.clearText(currentLang)),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: _transcribedText.isEmpty
                        ? null
                        : () {
                            Clipboard.setData(ClipboardData(text: _transcribedText));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('متن در کلیپ‌بورد کپی شد.'),
                                duration: Duration(seconds: 2),
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
                  onPressed: _toggleRecording,
                  backgroundColor: _isRecording ? Colors.redAccent : Colors.teal,
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                  label: Text(
                    _isRecording
                        ? AppStrings.stopRecording(currentLang)
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
