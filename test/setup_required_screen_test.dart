import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_of_aim_app/screens/setup_required_screen.dart';
import 'package:game_of_aim_app/theme/app_theme.dart';

/// Первый запуск без `--dart-define-from-file=env.json` не должен падать:
/// вместо игры открывается инструкция, где взять ключи.
void main() {
  testWidgets('без ключей показывается инструкция по env.json', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const SetupRequiredScreen()),
    );

    expect(find.text('Нужны ключи Supabase'), findsOneWidget);
    expect(find.textContaining('env.example.json'), findsOneWidget);
    expect(find.textContaining('--dart-define-from-file'), findsOneWidget);
  });

  testWidgets('ошибка инициализации выводится на экран настройки', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const SetupRequiredScreen(details: 'invalid api key'),
      ),
    );

    expect(find.textContaining('invalid api key'), findsOneWidget);
  });
}
