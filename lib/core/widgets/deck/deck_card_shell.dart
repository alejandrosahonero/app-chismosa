import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
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
    this.elevation = 3,
  });

  final Widget child;
  final Color? color;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // Paper, with a hairline edge and a soft warm shadow: a note on a table,
    // not a slab floating over the screen.
    return Material(
      color: color ?? context.semanticColors.paper,
      elevation: elevation,
      shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: child,
      ),
    );
  }
}
