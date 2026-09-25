import 'package:flutter/material.dart';

/// The Chismosa palette.
///
/// Hand-built, not seeded. A single seed through `ColorScheme.fromSeed` gives
/// the same pastel lilac every template app on the store has; this app is
/// meant to look like nothing else on the phone.
///
/// The idea behind it: **a note passed in secret**. Warm paper cards on sand,
/// written in plum ink, with a single hot colour for the thing that matters.
///
/// | Name | Hex | Role |
/// |---|---|---|
/// | Tinta | `#221029` | Text, dark background — plum, never pure black |
/// | Papel | `#FFF8F0` | The card: a note, not a panel |
/// | Arena | `#FBF1E6` | Light background |
/// | Picante | `#FF4B2B` | The brand colour: logo, like, dark primary |
/// | Picante hondo | `#D2301A` | Light primary: Picante darkened to pass 4.5:1 as text |
/// | Lavanda | `#B7A4FF` | Conversation: threads, aliases |
/// | Lima | `#D8F34A` | Rewards: chapters, goals, "new" |
///
/// Contrast is checked, not guessed: Tinta on Papel ~17:1, white on Picante
/// hondo 5.0:1, Tinta on Picante 5.4:1, Picante on dark Tinta 5.4:1.
abstract final class AppColors {
  static const Color ink = Color(0xFF221029);
  static const Color paper = Color(0xFFFFF8F0);
  static const Color sand = Color(0xFFFBF1E6);
  static const Color spice = Color(0xFFFF4B2B);
  static const Color spiceDeep = Color(0xFFD2301A);
  static const Color lavender = Color(0xFFB7A4FF);
  static const Color lime = Color(0xFFD8F34A);

  /// Kept for anything that still wants "the" brand colour in one constant:
  /// the splash, the notification accent, the share sheet.
  static const Color seed = spice;

  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFB26A00);

  static const ColorScheme light = ColorScheme(
    brightness: Brightness.light,
    primary: spiceDeep,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFFFDAD1),
    onPrimaryContainer: Color(0xFF3D0A02),
    secondary: Color(0xFF5B45BD),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFE8E0FF),
    onSecondaryContainer: Color(0xFF1D0A5C),
    tertiary: Color(0xFF4A5A00),
    onTertiary: Colors.white,
    tertiaryContainer: lime,
    onTertiaryContainer: Color(0xFF1B2200),
    error: Color(0xFFBA1A1A),
    onError: Colors.white,
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: sand,
    onSurface: ink,
    onSurfaceVariant: Color(0xFF6E5C72),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xFFF7EBDD),
    surfaceContainer: Color(0xFFF2E4D4),
    surfaceContainerHigh: Color(0xFFEDDDCB),
    surfaceContainerHighest: Color(0xFFE7D6C3),
    outline: Color(0xFFA8949F),
    outlineVariant: Color(0xFFE3D2C3),
    shadow: Color(0xFF3B1F2B),
    scrim: Colors.black,
    inverseSurface: ink,
    onInverseSurface: paper,
    inversePrimary: spice,
    surfaceTint: Colors.transparent,
  );

  static const ColorScheme dark = ColorScheme(
    brightness: Brightness.dark,
    primary: spice,
    onPrimary: ink,
    primaryContainer: Color(0xFF7A1A0B),
    onPrimaryContainer: Color(0xFFFFDAD1),
    secondary: lavender,
    onSecondary: Color(0xFF24135C),
    secondaryContainer: Color(0xFF3F2C8A),
    onSecondaryContainer: Color(0xFFE8E0FF),
    tertiary: lime,
    onTertiary: Color(0xFF1B2200),
    tertiaryContainer: Color(0xFF384500),
    onTertiaryContainer: lime,
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: Color(0xFF1A0C20),
    onSurface: Color(0xFFFFF1E6),
    onSurfaceVariant: Color(0xFFC9B6CB),
    surfaceContainerLowest: Color(0xFF14081A),
    surfaceContainerLow: Color(0xFF22122A),
    surfaceContainer: Color(0xFF2A1833),
    surfaceContainerHigh: Color(0xFF33203D),
    surfaceContainerHighest: Color(0xFF3D2948),
    outline: Color(0xFF8C7690),
    outlineVariant: Color(0xFF4A3553),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: paper,
    onInverseSurface: ink,
    inversePrimary: spiceDeep,
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
  /// table — and a warm plum in dark mode.
  final Color paper;
  final Color onPaper;

  /// The big opening quote mark on every card.
  final Color quote;

  static const AppSemanticColors light = AppSemanticColors(
    success: AppColors.success,
    warning: AppColors.warning,
    paper: AppColors.paper,
    onPaper: AppColors.ink,
    quote: AppColors.spice,
  );

  static const AppSemanticColors dark = AppSemanticColors(
    success: Color(0xFF8BD88F),
    warning: Color(0xFFFFB95C),
    paper: Color(0xFF2E1B38),
    onPaper: Color(0xFFFFF1E6),
    quote: AppColors.spice,
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
