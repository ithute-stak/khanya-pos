import 'package:flutter/material.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';

class KhanyaTheme {
  const KhanyaTheme._();

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: KhanyaBrand.forest,
      brightness: Brightness.light,
      primary: KhanyaBrand.forest,
      secondary: KhanyaBrand.gold,
      tertiary: KhanyaBrand.navy,
      surface: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: KhanyaBrand.mist,
      fontFamilyFallback: const ['Roboto', 'Arial', 'sans-serif'],
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: KhanyaBrand.navy,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE1E9E2)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        prefixIconColor: KhanyaBrand.forest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD7E2DA)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD7E2DA)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: KhanyaBrand.forest, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: KhanyaBrand.forest,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF0F6F1),
        side: const BorderSide(color: Color(0xFFD8E7DB)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: Colors.white,
        indicatorColor: KhanyaBrand.gold.withValues(alpha: 0.18),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: KhanyaBrand.forest,
        linearTrackColor: Color(0xFFE7EFE8),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFE1E9E2)),
    );
  }
}
