import 'package:flutter/material.dart';

import '../app/status_model.dart';

class AppColors {
  static const background = Color(0xFF07090C);
  static const surface = Color(0xFF10151C);
  static const surfaceHigh = Color(0xFF161C25);
  static const line = Color(0xFF2D3845);
  static const text = Color(0xFFE8ECF1);
  static const muted = Color(0xFF8A96A3);
  static const red = Color(0xFFFF2D3D);
  static const green = Color(0xFF27D17F);
  static const amber = Color(0xFFFFB020);
  static const blue = Color(0xFF3D8BFF);

  static Color light(Light light) => switch (light) {
        Light.green => green,
        Light.yellow => amber,
        Light.red => red,
        Light.off => const Color(0xFF4A5563),
      };
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.blue,
    brightness: Brightness.dark,
    surface: AppColors.surface,
    error: AppColors.red,
  ).copyWith(primary: AppColors.blue);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    textTheme: const TextTheme(
      displaySmall: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 4),
      titleLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
      labelLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(56, 52),
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.line)),
    ),
    sliderTheme: const SliderThemeData(trackHeight: 6),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
