import 'package:chismosa/core/config/app_config.dart';
import 'package:chismosa/core/widgets/deck/deck_swipe_progress.dart';
import 'package:flutter/foundation.dart';

/// How far a drag has to travel, per direction, before it counts as a gesture
/// rather than a hesitation.
///
/// Per deck rather than global because the same direction does not cost the
/// same everywhere: throwing a card away is cheap and should be easy, while
/// anything that takes the screen over — a share sheet, a thread — has to be
/// deliberate.
///
/// Horizontal fractions are of the card's **width** and vertical ones of its
/// **height**, which is why the vertical numbers are smaller for the same
/// physical distance: the card is much taller than it is wide.
@immutable
class DeckThresholds {
  const DeckThresholds({
    required this.left,
    required this.right,
    required this.up,
    required this.down,
    this.velocity = AppConfig.deckSwipeVelocity,
    this.requireTravel = const <DeckSwipeDirection>{},
  });

  final double left;
  final double right;
  final double up;
  final double down;

  /// Speed (logical px/s) that commits a gesture without covering the
  /// distance, so a quick flick works.
  final double velocity;

  /// Directions a flick alone cannot commit.
  ///
  /// For anything that covers the app, velocity is not enough evidence: a fast
  /// gesture that lands slightly off the intended axis would otherwise open a
  /// sheet the reader never asked for.
  final Set<DeckSwipeDirection> requireTravel;

  double forDirection(DeckSwipeDirection direction) => switch (direction) {
    DeckSwipeDirection.left => left,
    DeckSwipeDirection.right => right,
    DeckSwipeDirection.up => up,
    DeckSwipeDirection.down => down,
    DeckSwipeDirection.none => double.infinity,
  };
}
