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

  static String settingsTitle(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'تنظیمات' : 'Settings';

  static String modelManagementTitle(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'مدیریت مدل‌ها' : 'Model Management';

  static String modelManagementIntro(AppLanguage lang) =>
      lang == AppLanguage.persian
          ? 'مدل‌ها فقط با انتخاب شما دانلود می‌شوند. پس از راه‌اندازی اولیه، رونویسی به‌صورت آفلاین انجام می‌شود.'
          : 'Models download only when you choose. After initial setup, transcription runs offline.';

  static String fastModel(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'مدل سریع' : 'Fast Model';

  static String balancedModel(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'مدل متعادل' : 'Balanced Model';

  static String fastModelDescription(AppLanguage lang) =>
      lang == AppLanguage.persian
          ? 'دقت پایه، حجم کمتر، مناسب دستگاه‌های کم‌منبع'
          : 'Base accuracy, smaller download, suited to low-resource devices';

  static String balancedModelDescription(AppLanguage lang) =>
      lang == AppLanguage.persian
          ? 'دقت بیشتر، حجم بزرگ‌تر'
          : 'Higher accuracy, larger download';

  static String approximateSize(int bytes) =>
      '~${(bytes / 1000000).toStringAsFixed(0)} MB';

  static String downloadModel(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'دانلود مدل' : 'Download Model';

  static String pauseDownload(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'توقف' : 'Pause';

  static String resumeDownload(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'ادامه' : 'Resume';

  static String deleteModel(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'حذف مدل' : 'Delete Model';

  static String retryDownload(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'تلاش دوباره' : 'Retry';

  static String modelDownloading(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'در حال دانلود...' : 'Downloading...';

  static String modelVerifying(AppLanguage lang) => lang == AppLanguage.persian
      ? 'در حال بررسی SHA-256...'
      : 'Verifying SHA-256...';

  static String modelReady(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'آماده' : 'Ready';

  static String modelNotDownloaded(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'دانلود نشده' : 'Not downloaded';

  static String modelPaused(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'متوقف شده' : 'Paused';

  static String modelDownloadFailed(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'دانلود ناموفق بود' : 'Download failed';

  static String modelUnavailable(AppLanguage lang) => lang == AppLanguage.persian
      ? 'این مدل برای این پلتفرم در دسترس نیست.'
      : 'This model is not available for this platform.';

  static String modelManagementUnavailable(AppLanguage lang) =>
      lang == AppLanguage.persian
          ? 'دانلود مدل در این نسخه در دسترس نیست.'
          : 'Model downloads are not available in this build.';

  static String modelDeleteSuccess(AppLanguage lang) =>
      lang == AppLanguage.persian ? 'مدل حذف شد.' : 'Model deleted.';

  static String progressPercent(double fraction) =>
      '${(fraction.clamp(0, 1) * 100).round()}%';

  static String downloadSpeed(double bytesPerSecond) {
    final megabytes = bytesPerSecond / 1000000;
    return '${megabytes.toStringAsFixed(1)} MB/s';
  }
}
