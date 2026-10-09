import 'package:flutter/material.dart';

class AppTheme {
  // Ultra-high contrast color palette for visually impaired users
  static const Color background = Color(0xFF000000); // Deep AMOLED Black
  static const Color surface = Color(0xFF121212);
  static const Color surfaceLight = Color(0xFF222222);

  static const Color highVisYellow = Color(0xFFFFD600); // Prime accessibility amber
  static const Color cyanAccent = Color(0xFF00E5FF);    // Headphone / Audio active
  static const Color dangerRed = Color(0xFFFF3B30);     // Obstacle / Hazard alert
  static const Color safeGreen = Color(0xFF30D158);     // Clear path safe
  static const Color textWhite = Color(0xFFFFFFFF);
  static const Color textDim = Color(0xFFB0B0B0);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: highVisYellow,
      colorScheme: const ColorScheme.dark(
        primary: highVisYellow,
        secondary: cyanAccent,
        surface: surface,
        error: dangerRed,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: textWhite,
      ),
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: textWhite, letterSpacing: 0.5),
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textWhite),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: highVisYellow),
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textWhite),
        bodyLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.normal, color: textWhite, height: 1.4),
        bodyMedium: TextStyle(fontSize: 16, color: textDim),
      ),
    );
  }
}
