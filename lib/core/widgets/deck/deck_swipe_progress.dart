import 'package:flutter/foundation.dart';

/// Direction the top card of the deck is currently being dragged towards.
enum DeckSwipeDirection { none, left, right, up, down }

/// How far the top card has been dragged, and towards which action.
///
/// This is the single value the deck publishes while a finger is down. Both the
/// badge over the card and the round button underneath it read from here, so
/// they can never disagree about which action the current drag would fire.
@immutable
class DeckSwipeProgress {
  const DeckSwipeProgress({required this.direction, required this.amount});

  /// Nothing is being dragged.
  static const DeckSwipeProgress idle = DeckSwipeProgress(
    direction: DeckSwipeDirection.none,
    amount: 0,
  );

  final DeckSwipeDirection direction;

  /// 0 at rest, 1 once the drag has covered the distance that commits the
  /// action. Clamped at 1: past the threshold the feedback is already as loud
  /// as it gets, and letting it grow further would just look broken.
  final double amount;

  /// Amount for one specific direction, 0 for every other one.
  ///
  /// Only one direction can be active at a time — the deck picks the dominant
  /// axis — which is what stops two buttons from swelling at once.
  double amountFor(DeckSwipeDirection other) => direction == other ? amount : 0;

  /// Horizontal progress with a sign, for the card tilt: negative to the left,
  /// positive to the right, 0 while the drag is vertical.
  double get signedHorizontal => switch (direction) {
    DeckSwipeDirection.left => -amount,
    DeckSwipeDirection.right => amount,
    _ => 0,
  };

  @override
  bool operator ==(Object other) =>
      other is DeckSwipeProgress &&
      other.direction == direction &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(direction, amount);

  @override
  String toString() =>
      'DeckSwipeProgress(${direction.name}, ${amount.toStringAsFixed(2)})';
}
