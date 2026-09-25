import 'package:chismosa/core/theme/app_colors.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Material 3 themes for the app, built on the hand-made palette in
/// [AppColors].
///
/// Dynamic colour (Material You) is deliberately **not** used: on most phones
/// it would repaint Chismosa in the wallpaper's colours, and a brand that
/// changes with the wallpaper is not a brand.
abstract final class AppTheme {
  static ThemeData light() => _build(AppColors.light, AppSemanticColors.light);

  static ThemeData dark() => _build(AppColors.dark, AppSemanticColors.dark);

  static ThemeData _build(ColorScheme scheme, AppSemanticColors semantic) {
    // Roboto named explicitly: it is Android's default anyway, and naming it
    // makes the screenshot tool render every widget with the real font.
    final ThemeData base = ThemeData(colorScheme: scheme, fontFamily: 'Roboto');

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
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const StadiumBorder(),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        selectedColor: scheme.inverseSurface,
        secondarySelectedColor: scheme.inverseSurface,
        checkmarkColor: scheme.onInverseSurface,
        labelStyle: base.textTheme.labelLarge?.copyWith(
          color: scheme.onSurface,
        ),
        secondaryLabelStyle: base.textTheme.labelLarge?.copyWith(
          color: scheme.onInverseSurface,
        ),
        showCheckmark: false,
      ),
      textTheme: base.textTheme.copyWith(
        // Tighter and heavier than Material's defaults: the story is the
        // interface, and it should read like a voice, not like a form.
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
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
