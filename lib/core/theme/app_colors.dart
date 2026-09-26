import 'package:flutter/material.dart';

/// The Chismosa palette: "Rojo sangre".
///
/// Hand-built, not seeded, and chosen by the owner over several rounds of
/// mockups: a love letter and a scandal. Blood red on bone, a deep maroon
/// header, near-black red ink.
///
/// | Name | Hex | Role |
/// |---|---|---|
/// | Granate | `#4A0000` | The header, the welcome, the share image, the icon ground |
/// | Sangre | `#880808` | The brand colour: primary, like, quote mark, pills |
/// | Tinta | `#1E0B0B` | Text — red-black, never pure black |
/// | Hueso | `#F4EFEA` | Light background |
/// | Papel | `#FFFFFF` | The card |
/// | Polvo | `#C9A9A0` | Quiet accents: chapter pill, links on maroon |
///
/// Contrast: Tinta on Papel ~19:1, white on Sangre 9.3:1, white on Granate
/// 14:1, Sangre on Hueso 8.2:1. Sangre is too dark to read on the dark theme's
/// background, so dark mode uses a lifted red (#FF6B63) as primary.
abstract final class AppColors {
  static const Color maroon = Color(0xFF4A0000);
  static const Color blood = Color(0xFF880808);
  static const Color ink = Color(0xFF1E0B0B);
  static const Color bone = Color(0xFFF4EFEA);
  static const Color paper = Color(0xFFFFFFFF);
  static const Color dust = Color(0xFFC9A9A0);

  /// Primary on the dark theme: Sangre lifted until it reads on near-black.
  static const Color bloodLight = Color(0xFFFF6B63);

  /// "The" brand colour in one constant: splash, notification accent.
  static const Color seed = blood;

  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFB26A00);

  static const ColorScheme light = ColorScheme(
    brightness: Brightness.light,
    primary: blood,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFF6DAD7),
    onPrimaryContainer: maroon,
    secondary: blood,
    onSecondary: Colors.white,
    secondaryContainer: blood,
    onSecondaryContainer: Colors.white,
    tertiary: Color(0xFF6E4A43),
    onTertiary: Colors.white,
    tertiaryContainer: dust,
    onTertiaryContainer: ink,
    error: Color(0xFFBA1A1A),
    onError: Colors.white,
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: bone,
    onSurface: ink,
    onSurfaceVariant: Color(0xFF7A5F5B),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xFFEFE8E2),
    surfaceContainer: Color(0xFFE9E0D9),
    surfaceContainerHigh: Color(0xFFE3D8D0),
    surfaceContainerHighest: Color(0xFFDCCFC6),
    outline: Color(0xFFA88C86),
    outlineVariant: Color(0xFFE2D6CF),
    shadow: Color(0xFF2A0A0A),
    scrim: Colors.black,
    inverseSurface: ink,
    onInverseSurface: bone,
    inversePrimary: bloodLight,
    surfaceTint: Colors.transparent,
  );

  static const ColorScheme dark = ColorScheme(
    brightness: Brightness.dark,
    primary: bloodLight,
    onPrimary: Color(0xFF2A0000),
    primaryContainer: blood,
    onPrimaryContainer: Color(0xFFFFDAD6),
    secondary: bloodLight,
    onSecondary: Color(0xFF2A0000),
    secondaryContainer: blood,
    onSecondaryContainer: Colors.white,
    tertiary: dust,
    onTertiary: ink,
    tertiaryContainer: Color(0xFF5A403B),
    onTertiaryContainer: Color(0xFFF4E0DA),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF140707),
    onSurface: bone,
    onSurfaceVariant: Color(0xFFCDB6B0),
    surfaceContainerLowest: Color(0xFF0E0404),
    surfaceContainerLow: Color(0xFF1C0C0B),
    surfaceContainer: Color(0xFF231110),
    surfaceContainerHigh: Color(0xFF2C1715),
    surfaceContainerHighest: Color(0xFF361E1B),
    outline: Color(0xFF8E726C),
    outlineVariant: Color(0xFF4A2F2B),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: bone,
    onInverseSurface: ink,
    inversePrimary: blood,
    surfaceTint: Colors.transparent,
  );
}

/// Colours Material has no slot for, resolved per brightness and exposed as
/// `context.semanticColors`.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.paper,
    required this.onPaper,
    required this.quote,
  });

  final Color success;
  final Color warning;

  /// The story card. Lighter than the background in light mode — paper on a
  /// table — and a deep red-brown in dark mode.
  final Color paper;
  final Color onPaper;

  /// The big opening quote mark on every card.
  final Color quote;

  static const AppSemanticColors light = AppSemanticColors(
    success: AppColors.success,
    warning: AppColors.warning,
    paper: AppColors.paper,
    onPaper: AppColors.ink,
    quote: AppColors.blood,
  );

  static const AppSemanticColors dark = AppSemanticColors(
    success: Color(0xFF8BD88F),
    warning: Color(0xFFFFB95C),
    paper: Color(0xFF231110),
    onPaper: AppColors.bone,
    quote: AppColors.bloodLight,
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? paper,
    Color? onPaper,
    Color? quote,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      paper: paper ?? this.paper,
      onPaper: onPaper ?? this.onPaper,
      quote: quote ?? this.quote,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      paper: Color.lerp(paper, other.paper, t) ?? paper,
      onPaper: Color.lerp(onPaper, other.onPaper, t) ?? onPaper,
      quote: Color.lerp(quote, other.quote, t) ?? quote,
    );
  }
}
