import 'package:aja/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Common frame for everything the deck renders.
///
/// Ad cards use the exact same shell as content cards — that is what makes the
/// ad slot feel native — but they always carry a visible "Ad" label, which is
/// both an AdMob policy requirement and the thing that keeps the app out of the
/// "deceptive ads" bucket in review.
class DeckCardShell extends StatelessWidget {
  const DeckCardShell({
    required this.child,
    super.key,
    this.color,
    this.elevation = 6,
  });

  final Widget child;
  final Color? color;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: color ?? theme.colorScheme.surfaceContainerHigh,
      elevation: elevation,
      surfaceTintColor: theme.colorScheme.primary,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: child,
      ),
    );
  }
}
