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

  static String emptyTranscription(AppLanguage lang) =>
      lang == AppLanguage.persian
          ? 'متن استخراج‌شده در اینجا نمایش داده می‌شود...'
          : 'Transcribed text will appear here...';

  static String copyText(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'کپی متن' : 'Copy Text';

  static String clearText(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'پاک‌سازی' : 'Clear';
}
