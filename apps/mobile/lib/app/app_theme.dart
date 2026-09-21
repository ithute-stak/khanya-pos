import 'package:flutter/material.dart';

class KhanyaTheme {
  const KhanyaTheme._();

  static const primary = Color(0xFF08713A);
  static const secondary = Color(0xFF49A91B);
  static const navy = Color(0xFF0A3654);
  static const gold = Color(0xFFD39A13);
  static const surface = Color(0xFFF7FAF6);

  static ThemeData get light {
    final seeded = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      surface: surface,
    );
    final scheme = seeded.copyWith(
      primary: primary,
      onPrimary: Colors.white,
      secondary: secondary,
      tertiary: gold,
      surface: surface,
      onSurface: navy,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF3F7F2),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF3F7F2),
        foregroundColor: navy,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFDDE8DC)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFCEDCCD)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFCEDCCD)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFDDE8DC)),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
    );
  }
}
