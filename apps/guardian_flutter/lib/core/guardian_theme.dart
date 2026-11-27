import 'package:flutter/material.dart';

abstract final class GuardianPalette {
  static const bg = Color(0xFF06101F);
  static const surface = Color(0xFF0C1B2E);
  static const elevated = Color(0xFF12253A);
  static const line = Color(0xFF29445F);
  static const teal = Color(0xFF55D5FF);
  static const blue = Color(0xFF69A6FF);
  static const amber = Color(0xFFFFBD69);
  static const red = Color(0xFFFF777E);
  static const muted = Color(0xFF96ABBE);
  static const white = Color(0xFFF3F8FA);
}

ThemeData guardianTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: GuardianPalette.teal,
    brightness: Brightness.dark,
    surface: GuardianPalette.surface,
    error: GuardianPalette.red,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: GuardianPalette.bg,
    colorScheme: scheme,
    cardTheme: CardThemeData(
      color: GuardianPalette.surface,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: GuardianPalette.line, width: .7),
        borderRadius: BorderRadius.circular(22),
      ),
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: GuardianPalette.elevated,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      hintStyle: const TextStyle(color: GuardianPalette.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: GuardianPalette.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: GuardianPalette.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: GuardianPalette.teal)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: GuardianPalette.elevated,
      contentTextStyle: const TextStyle(color: GuardianPalette.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: GuardianPalette.teal,
        foregroundColor: GuardianPalette.bg,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: GuardianPalette.white,
        side: const BorderSide(color: GuardianPalette.line),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: GuardianPalette.surface,
      indicatorColor: GuardianPalette.elevated,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(color: GuardianPalette.white, fontSize: 11)),
    ),
    dividerTheme: const DividerThemeData(color: GuardianPalette.line),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w900,
        color: GuardianPalette.white, letterSpacing: -1.3),
      headlineMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.w900,
        color: GuardianPalette.white, letterSpacing: -.8),
      titleLarge: TextStyle(fontWeight: FontWeight.w800, color: GuardianPalette.white),
      titleMedium: TextStyle(fontWeight: FontWeight.w800, color: GuardianPalette.white),
      bodyLarge: TextStyle(color: GuardianPalette.white),
      bodyMedium: TextStyle(color: GuardianPalette.white),
      bodySmall: TextStyle(color: GuardianPalette.muted),
    ),
  );
}