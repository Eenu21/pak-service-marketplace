import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const brandNavy = Color(0xFF0F2D4A);
  static const brandBlue = Color(0xFF1C5FA8);
  static const brandTeal = Color(0xFF0FA589);
  static const accentOrange = Color(0xFFE18D37);
  static const brandSand = Color(0xFFF6EFE4);
  static const surface = Color(0xFFF3F7FC);
  static const border = Color(0xFFD8E1ED);

  static TextTheme _withUrduLineHeight(TextTheme textTheme) {
    TextStyle? withHeight(TextStyle? style) => style?.copyWith(height: 1.3);

    return textTheme.copyWith(
      displayLarge: withHeight(textTheme.displayLarge),
      displayMedium: withHeight(textTheme.displayMedium),
      displaySmall: withHeight(textTheme.displaySmall),
      headlineLarge: withHeight(textTheme.headlineLarge),
      headlineMedium: withHeight(textTheme.headlineMedium),
      headlineSmall: withHeight(textTheme.headlineSmall),
      titleLarge: withHeight(textTheme.titleLarge),
      titleMedium: withHeight(textTheme.titleMedium),
      titleSmall: withHeight(textTheme.titleSmall),
      bodyLarge: withHeight(textTheme.bodyLarge),
      bodyMedium: withHeight(textTheme.bodyMedium),
      bodySmall: withHeight(textTheme.bodySmall),
      labelLarge: withHeight(textTheme.labelLarge),
      labelMedium: withHeight(textTheme.labelMedium),
      labelSmall: withHeight(textTheme.labelSmall),
    );
  }

  static ThemeData light({Locale? locale}) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: brandBlue,
        onPrimary: Colors.white,
        secondary: brandTeal,
        onSecondary: Colors.white,
        tertiary: accentOrange,
        surface: Colors.white,
        onSurface: brandNavy,
        error: Color(0xFFC72C41),
      ),
      scaffoldBackgroundColor: surface,
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: brandBlue, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brandBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: const BorderSide(color: border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFDDEBFF),
        height: 70,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ),
    );

    final isUrdu = locale?.languageCode == 'ur';
    final baseTextTheme = isUrdu
        ? GoogleFonts.notoNaskhArabicTextTheme(base.textTheme)
        : GoogleFonts.plusJakartaSansTextTheme(base.textTheme);
    final textTheme = isUrdu
        ? _withUrduLineHeight(baseTextTheme)
        : baseTextTheme;
    final basePrimaryTextTheme = isUrdu
        ? GoogleFonts.notoNaskhArabicTextTheme(base.primaryTextTheme)
        : GoogleFonts.plusJakartaSansTextTheme(base.primaryTextTheme);

    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: isUrdu
          ? _withUrduLineHeight(basePrimaryTextTheme)
          : basePrimaryTextTheme,
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        side: const BorderSide(color: border),
        selectedColor: const Color(0xFFDBEAFE),
        backgroundColor: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        surfaceTintColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: brandNavy,
        centerTitle: false,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      dividerColor: border,
    );
  }
}
