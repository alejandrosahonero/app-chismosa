import 'package:aja/core/theme/app_colors.dart';
import 'package:aja/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Material 3 themes for the app.
///
/// Both themes are generated from a single seed colour ([AppColors.seed]), so a
/// new app only needs to change that constant. If you later want Android 12+
/// wallpaper colours, pass the dynamic scheme through [light]/[dark] instead of
/// the seeded fallback — the rest of the theme is already scheme-driven.
abstract final class AppTheme {
  static ThemeData light([ColorScheme? dynamicScheme]) => _build(
    dynamicScheme ?? ColorScheme.fromSeed(seedColor: AppColors.seed),
    AppSemanticColors.light,
  );

  static ThemeData dark([ColorScheme? dynamicScheme]) => _build(
    dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: AppColors.darkSeed,
          brightness: Brightness.dark,
        ),
    AppSemanticColors.dark,
  );

  static ThemeData _build(ColorScheme scheme, AppSemanticColors semantic) {
    final ThemeData base = ThemeData(colorScheme: scheme);

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      extensions: <ThemeExtension<dynamic>>[semantic],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 3,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        insetPadding: EdgeInsets.all(AppSpacing.md),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.lg)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
        ),
      ),
    );
  }
}
