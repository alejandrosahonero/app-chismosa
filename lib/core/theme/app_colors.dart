import 'package:flutter/material.dart';

/// Brand palette.
///
/// A single seed colour drives the whole Material 3 scheme, so re-skinning a
/// new app built on this template is a one-line change. Extra semantic colours
/// that Material does not provide live in [AppSemanticColors].
abstract final class AppColors {
  /// Change this to re-brand the app.
  static const Color seed = Color(0xFFC026D3);

  /// Optional second seed for the dark scheme. Keeping it equal to [seed]
  /// gives a consistent hue across both themes.
  static const Color darkSeed = seed;

  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
}

/// Semantic colours resolved per brightness and exposed through
/// `Theme.of(context).extension<AppSemanticColors>()`.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({required this.success, required this.warning});

  final Color success;
  final Color warning;

  static const AppSemanticColors light = AppSemanticColors(
    success: AppColors.success,
    warning: AppColors.warning,
  );

  static const AppSemanticColors dark = AppSemanticColors(
    success: Color(0xFF4ADE80),
    warning: Color(0xFFFBBF24),
  );

  @override
  AppSemanticColors copyWith({Color? success, Color? warning}) {
    return AppSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
    );
  }
}
