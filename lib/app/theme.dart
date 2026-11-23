import 'package:flutter/material.dart';

/// Mat, koyu kurgu masası paleti. Parlak renk yok; vurgu rengi soluk çelik mavisi.
class AppColors {
  AppColors._();

  static const background = Color(0xFF0D0E10);
  static const panel = Color(0xFF15161A);
  static const panelHeader = Color(0xFF1A1B20);
  static const raised = Color(0xFF202127);
  static const thumbBg = Color(0xFF0A0A0C);
  static const border = Color(0xFF2A2B31);
  static const borderStrong = Color(0xFF3A3C44);
  static const handle = Color(0xFF45474F);

  static const textPrimary = Color(0xFFE3E4E8);
  static const textSecondary = Color(0xFF9C9EA6);
  static const textDisabled = Color(0xFF5A5C64);

  static const accent = Color(0xFF7F9CB8);
  static const selectedBg = Color(0xFF1F2833);
  static const activeBg = Color(0xFF2A3440);

  static const danger = Color(0xFFC0645C);
  static const ok = Color(0xFF7FA88A);
  static const warn = Color(0xFFC9A55C);

  static const videoLane = Color(0xFF1C242D);
  static const audioLane = Color(0xFF1B2620);
  static const audioTint = Color(0xFF16201A);
  static const playhead = Color(0xFFD0D3D8);
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: AppColors.background,
    secondary: AppColors.textSecondary,
    onSecondary: AppColors.background,
    surface: AppColors.panel,
    onSurface: AppColors.textPrimary,
    error: AppColors.danger,
    onError: AppColors.background,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    dividerColor: AppColors.border,
    splashFactory: NoSplash.splashFactory,
    visualDensity: VisualDensity.compact,
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.border,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.raised,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.raised,
      contentTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 13),
      actionTextColor: AppColors.accent,
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 13, color: AppColors.textPrimary),
      bodySmall: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.35),
      titleSmall: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: 0.2,
      ),
    ),
  );
}
