import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppLanguage {
  persian(Locale('fa', 'IR'), TextDirection.rtl, 'فارسی'),
  english(Locale('en', 'US'), TextDirection.ltr, 'English');

  final Locale locale;
  final TextDirection direction;
  final String label;

  const AppLanguage(this.locale, this.direction, this.label);
}

class LocaleNotifier extends StateNotifier<AppLanguage> {
  LocaleNotifier() : super(AppLanguage.persian);

  void toggleLanguage() {
    state = state == AppLanguage.persian ? AppLanguage.english : AppLanguage.persian;
  }

  void setLanguage(AppLanguage lang) {
    state = lang;
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, AppLanguage>((ref) {
  return LocaleNotifier();
});

/// کلاس ساده نگاشت متن‌ها (کامل‌تر در مراحل بعد به ARB یا Dictionary ارتقا می‌یابد)
class AppStrings {
  static String title(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'رونویس فارسی' : 'Persian Transcriber';

  static String subtitle(AppLanguage lang) =>
      lang == AppLanguage.persian
          ? 'تبدیل محلی گفتار به متن | بدون ارسال داده به ابر'
          : 'Local Speech-to-Text | Zero Cloud Data Transmission';

  static String startRecording(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'شروع ضبط و رونویسی' : 'Start Recording';

  static String stopRecording(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'توقف ضبط' : 'Stop Recording';

  static String cancelTranscription(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'لغو رونویسی' : 'Cancel';

  static String recording(AppLanguage lang) => lang == AppLanguage.persian
      ? 'در حال ضبط از میکروفون...'
      : 'Recording from microphone...';

  static String emptyTranscription(AppLanguage lang) =>
      lang == AppLanguage.persian
          ? 'متن استخراج‌شده در اینجا نمایش داده می‌شود...'
          : 'Transcribed text will appear here...';

  static String copyText(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'کپی متن' : 'Copy Text';

  static String clearText(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'پاک‌سازی' : 'Clear';

  static String checkingEngine(AppLanguage lang) => lang == AppLanguage.persian
      ? 'در حال آماده‌سازی موتور محلی...'
      : 'Preparing the local engine...';

  static String checkingModel(AppLanguage lang) =>
      lang == AppLanguage.persian
          ? 'در حال بررسی مدل محلی...'
          : 'Checking the local model...';

  static String preparingAudio(AppLanguage lang) => lang == AppLanguage.persian
      ? 'در حال آماده‌سازی صوت...'
      : 'Preparing audio...';

  static String loadingModel(AppLanguage lang) => lang == AppLanguage.persian
      ? 'در حال بارگذاری مدل...'
      : 'Loading the model...';

  static String transcribing(AppLanguage lang) => lang == AppLanguage.persian
      ? 'در حال رونویسی...'
      : 'Transcribing...';

  static String cleaningUp(AppLanguage lang) => lang == AppLanguage.persian
      ? 'در حال پاک‌سازی فایل‌های موقت...'
      : 'Cleaning up temporary files...';

  static String transcriptionCompleted(AppLanguage lang) =>
      lang == AppLanguage.persian
          ? 'رونویسی کامل شد.'
          : 'Transcription complete.';

  static String transcriptionCancelled(AppLanguage lang) =>
      lang == AppLanguage.persian
          ? 'رونویسی لغو شد.'
          : 'Transcription cancelled.';

  static String transcriptionFailed(AppLanguage lang) =>
      lang == AppLanguage.persian
          ? 'رونویسی ناموفق بود.'
          : 'Transcription failed.';

  static String engineUnavailable(AppLanguage lang) =>
      lang == AppLanguage.persian
          ? 'موتور رونویسی محلی در این نسخه هنوز فعال نیست.'
          : 'The local transcription engine is not available in this build.';

  static String engineNotReady(AppLanguage lang) => lang == AppLanguage.persian
      ? 'موتور رونویسی آماده نیست.'
      : 'The transcription engine is not ready.';

  static String microphonePermissionDenied(AppLanguage lang) =>
      lang == AppLanguage.persian
          ? 'دسترسی به میکروفون داده نشد. آن را در تنظیمات حریم خصوصی ویندوز فعال کنید.'
          : 'Microphone access was denied. Enable it in Windows privacy settings.';

  static String copySuccess(AppLanguage lang) => lang == AppLanguage.persian
      ? 'متن در کلیپ‌بورد کپی شد.'
      : 'Text copied to clipboard.';
}
