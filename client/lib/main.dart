import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/l10n/app_locale.dart';
import 'core/theme/app_theme.dart';
import 'features/transcriber/presentation/transcriber_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: PersianTranscriberApp(),
    ),
  );
}

class PersianTranscriberApp extends ConsumerWidget {
  const PersianTranscriberApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLanguage = ref.watch(localeProvider);

    return MaterialApp(
      title: AppStrings.title(currentLanguage),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      locale: currentLanguage.locale,
      supportedLocales: const [
        Locale('fa', 'IR'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Directionality(
        textDirection: currentLanguage.direction,
        child: const TranscriberScreen(),
      ),
    );
  }
}
