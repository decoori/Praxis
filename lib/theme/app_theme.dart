import 'package:flutter/material.dart';

/// Тема приложения: тёмный фон, золотой акцент, шрифт Nunito из assets.
///
/// Вынесена из main.dart, чтобы экран настройки (когда не заданы ключи
/// Supabase) выглядел так же, как сама игра.
ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0F1015),
    // Шрифт берётся из assets/fonts, без сетевой загрузки.
    fontFamily: 'Nunito',
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFFF5A623),
      surface: Color(0xFF1A1D24),
      onSurface: Colors.white,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF14171E),
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0x28FFFFFF), width: 1.2),
      ),
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 13,
      ),
    ),
    // Раньше здесь был GoogleFonts.nunitoTextTheme: он скачивал шрифт
    // при первом кадре и подменял его после загрузки. Теперь шрифт
    // подставляется через fontFamily, а цвета остаются как были.
    textTheme: ThemeData.dark().textTheme.apply(
      fontFamily: 'Nunito',
      bodyColor: const Color(0xFFFFFFFF),
      displayColor: const Color(0xFFFFFFFF),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1A1D24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0x14FFFFFF), width: 1),
      ),
    ),
  );
}
