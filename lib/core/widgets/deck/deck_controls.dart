import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
import 'package:chismosa/core/widgets/deck/deck_swipe_progress.dart';
import 'package:flutter/material.dart';

/// Tint each direction answers in.
///
/// One mapping for every deck in the app: the colour is how a reader learns
/// that the badge which appeared over the card and the button that swelled
/// underneath it are the same action, so two decks disagreeing about it would
/// unteach that.
extension DeckDirectionColor on DeckSwipeDirection {
  Color color(BuildContext context) => switch (this) {
    DeckSwipeDirection.left => context.colors.onSurfaceVariant,
    DeckSwipeDirection.right => context.colors.primary,
    DeckSwipeDirection.up => context.colors.secondary,
    DeckSwipeDirection.down => context.colors.onSurfaceVariant,
    DeckSwipeDirection.none => context.colors.outline,
  };
}

/// One round control: a tinted ring over the surface colour, with the icon in
/// the same tint.
///
/// It listens to [progress] on its own instead of taking a plain number, so a
/// drag repaints a handful of small buttons and nothing else on the screen.
///
/// These buttons are **not decorative**. A drag-only interface is unusable with
/// a screen reader and is penalised by Play's accessibility scan. Do not remove
/// them.
class DeckActionButton extends StatelessWidget {
  const DeckActionButton({
    required this.icon,
    required this.direction,
    required this.progress,
    required this.tooltip,
    required this.onPressed,
    super.key,
    this.diameter = large,
  });

  /// Comfortably past the 48dp minimum touch target on both sizes.
  static const double large = 64;
  static const double small = 52;

  /// How much bigger the button gets at the commit threshold. Enough to be
  /// unmistakable, small enough that the row never collides.
  static const double maxZoom = 0.4;

  final IconData icon;

  /// The gesture this button answers to.
  final DeckSwipeDirection direction;

  final ValueNotifier<DeckSwipeProgress> progress;
  final String tooltip;

  /// Null disables the button, which happens while a card that cannot be acted
  /// on — an ad slot — is on top.
  final VoidCallback? onPressed;

  final double diameter;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final Color color = direction.color(context);

    return Tooltip(
      message: tooltip,
      child: ValueListenableBuilder<DeckSwipeProgress>(
        valueListenable: progress,
        builder: (BuildContext context, DeckSwipeProgress value, Widget? _) {
          // A disabled button belongs to a card that cannot be acted on, so it
          // must not answer the drag either.
          final double t = enabled
              ? Curves.easeOut.transform(value.amountFor(direction))
              : 0;

          // Faded rather than greyed: the button keeps its identity while it
          // waits. Under the finger it does the opposite, filling in with its
          // own tint until it reads as pressed.
          final Color tint = enabled ? color : color.withValues(alpha: 0.3);

          return Transform.scale(
            scale: 1 + maxZoom * t,
            child: SizedBox.square(
              dimension: diameter,
              child: Material(
                color: Color.lerp(
                  context.colors.surface,
                  tint.withValues(alpha: 0.2),
                  t,
                ),
                elevation: enabled ? 2 + 6 * t : 0,
                shadowColor: context.colors.shadow,
                shape: CircleBorder(
                  side: BorderSide(
                    color: tint.withValues(alpha: 0.4 + 0.6 * t),
                    width: 1 + t,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPressed,
                  child: Center(
                    child: Icon(icon, color: tint, size: diameter * 0.42),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One badge: a filled disc that fades and swells with the drag.
///
/// It belongs on the edge **opposite** the gesture. The edge the card is
/// heading towards leaves the screen, and would take the icon with it exactly
/// when it is confirming what is about to happen.
class DeckSwipeBadge extends StatelessWidget {
  const DeckSwipeBadge({
    required this.icon,
    required this.direction,
    required this.alignment,
    required this.amount,
    super.key,
  });

  final IconData icon;
  final DeckSwipeDirection direction;
  final AlignmentGeometry alignment;

  /// 0 at rest, 1 at the commit threshold.
  final double amount;

  @override
  Widget build(BuildContext context) {
    if (amount <= 0) return const SizedBox.shrink();

    final double t = Curves.easeOut.transform(amount.clamp(0.0, 1.0));
    final Color color = direction.color(context);

    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Opacity(
          // Faster than the scale so the badge is legible well before the
          // threshold: the point is to tell the user what will happen while
          // there is still time to change their mind.
          opacity: (t * 1.6).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.65 + 0.45 * t,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                // A ring in the deck's surface colour, so the disc stays
                // readable over either face of the card.
                border: Border.all(
                  color: context.colors.surfaceContainerHigh,
                  width: 3,
                ),
              ),
              child: Icon(
                icon,
                size: 30,
                color:
                    ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
