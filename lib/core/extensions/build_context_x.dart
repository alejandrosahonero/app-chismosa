import 'package:aja/core/theme/app_colors.dart';
import 'package:aja/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// Shorthands for the three lookups that appear in almost every widget.
extension BuildContextX on BuildContext {
  ThemeData get theme => Theme.of(this);

  ColorScheme get colors => Theme.of(this).colorScheme;

  TextTheme get texts => Theme.of(this).textTheme;

  AppSemanticColors get semanticColors =>
      Theme.of(this).extension<AppSemanticColors>() ?? AppSemanticColors.light;

  /// Localized strings. Non-nullable thanks to `nullable-getter: false`.
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// Shows a floating snack bar, replacing any previous one so a burst of
  /// events cannot queue up several seconds of messages.
  void showSnack(String message) {
    ScaffoldMessenger.of(this)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
