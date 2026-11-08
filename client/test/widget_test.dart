import 'package:client/features/transcriber/presentation/transcriber_screen.dart';
import 'package:client/features/transcriber/presentation/transcription_providers.dart';
import 'package:client/main.dart';
import 'package:client/platform/transcription_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget buildApp() {
  return ProviderScope(
    overrides: [
      transcriptionCoordinatorProvider
          .overrideWith(createTranscriptionCoordinator),
    ],
    child: const PersianTranscriberApp(),
  );
}

void main() {
  testWidgets('renders the Persian shell by default', (tester) async {
    await tester.pumpWidget(buildApp());

    expect(find.byType(TranscriberScreen), findsOneWidget);
    expect(find.text('رونویس فارسی'), findsOneWidget);
    expect(
      find.text('تبدیل محلی گفتار به متن | بدون ارسال داده به ابر'),
      findsOneWidget,
    );
    expect(
      find.text('متن استخراج‌شده در اینجا نمایش داده می‌شود...'),
      findsOneWidget,
    );
    expect(find.text('شروع ضبط و رونویسی'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(TranscriberScreen))),
      TextDirection.rtl,
    );
  });

  testWidgets('language toggle updates visible strings', (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.tap(find.byIcon(Icons.language));
    await tester.pumpAndSettle();

    expect(find.text('Persian Transcriber'), findsOneWidget);
    expect(
      find.text('Local Speech-to-Text | Zero Cloud Data Transmission'),
      findsOneWidget,
    );
    expect(find.text('Transcribed text will appear here...'), findsOneWidget);
    expect(find.text('Start Recording'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(TranscriberScreen))),
      TextDirection.ltr,
    );
  });

  testWidgets('microphone action surfaces the unavailable engine status',
      (tester) async {
    await tester.pumpWidget(buildApp());

    await tester.tap(find.text('شروع ضبط و رونویسی'));
    await tester.pumpAndSettle();

    expect(
      find.text('موتور رونویسی محلی در این نسخه هنوز فعال نیست.'),
      findsOneWidget,
    );
    expect(
      find.text('Native FFI inference has not been implemented or validated.'),
      findsOneWidget,
    );
    expect(find.text('شروع ضبط و رونویسی'), findsOneWidget);
  });
}
