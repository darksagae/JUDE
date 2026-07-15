import 'package:flutter/material.dart';

/// Palette lifted from the web app's Tailwind usage.
class AppColors {
  static const indigo = Color(0xFF4F46E5);
  static const indigo700 = Color(0xFF4338CA);
  static const emerald = Color(0xFF059669);
  static const emerald500 = Color(0xFF10B981);
  static const amber = Color(0xFFF59E0B);
  static const amber600 = Color(0xFFD97706);
  static const rose = Color(0xFFE11D48);
  static const red = Color(0xFFEF4444);
  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate600 = Color(0xFF475569);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);
  static const slate900 = Color(0xFF0F172A);
  static const slate950 = Color(0xFF020617);
  static const workerBg = Color(0xFF0B0F19);
  static const workerPanel = Color(0xFF111827);

  // Chart palette (matches recharts COLORS array)
  static const chart = [
    Color(0xFF4F46E5),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
  ];
}

/// Light theme used by the manager (supervisor) portal.
ThemeData managerTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: AppColors.indigo,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.slate50,
    fontFamily: 'Roboto',
  );
  return base.copyWith(
    // Force strong near-black default text so any un-coloured text on a white
    // surface (including the worker station's light content area) reads clearly
    // instead of a muted grey.
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.slate900,
      displayColor: AppColors.slate900,
    ),
    colorScheme: base.colorScheme.copyWith(
      onSurface: AppColors.slate900,
      onSurfaceVariant: AppColors.slate700,
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.slate100),
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    inputDecorationTheme: _inputTheme(false),
  );
}

/// Dark theme used by the worker (checkout) station.
ThemeData workerTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorSchemeSeed: AppColors.emerald,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.workerBg,
    fontFamily: 'Roboto',
  );
  return base.copyWith(
    cardTheme: const CardThemeData(
      elevation: 0,
      color: AppColors.workerPanel,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.slate800),
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
    inputDecorationTheme: _inputTheme(true),
  );
}

InputDecorationTheme _inputTheme(bool dark) => InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: dark ? AppColors.slate900 : AppColors.slate50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
            color: dark ? AppColors.slate800 : AppColors.slate200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
            color: dark ? AppColors.slate800 : AppColors.slate200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.indigo, width: 1.5),
      ),
    );
