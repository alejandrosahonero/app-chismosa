import 'package:aja/features/goals/domain/rank.dart';
import 'package:flutter/foundation.dart';

/// Everything the goal ring and the progress screen paint.
@immutable
class GoalsState {
  const GoalsState({
    required this.epochDay,
    required this.target,
    required this.learned,
    required this.points,
    required this.awarded,
  });

  /// The calendar day this state describes. Compared against the clock on every
  /// write so a session left open across midnight rolls over by itself.
  final int epochDay;

  /// Facts today asks for.
  final int target;

  /// Facts learned today. Can exceed [target] — reading past the goal is not
  /// punished, it just stops paying.
  final int learned;

  /// Lifetime points.
  final int points;

  /// Whether today's goal has already been paid out. Separate from
  /// `learned >= target` because the payout happens once and the count keeps
  /// going up after it.
  final bool awarded;

  Rank get rank => Rank.forPoints(points);

  bool get isComplete => learned >= target;

  /// Facts left, floored at zero.
  int get remaining => (target - learned).clamp(0, target);

  /// 0→1 for the ring. Clamped, so an over-achieved day shows a full circle
  /// rather than an overshoot.
  double get progress => target <= 0 ? 1 : (learned / target).clamp(0.0, 1.0);
}

/// What registering a fact turned out to be worth.
///
/// A sealed result rather than a bool: the caller has three different things to
/// say — nothing, "goal met", "goal met and you moved up" — and the third one
/// interrupts the user while the second one does not.
sealed class GoalEvent {
  const GoalEvent();
}

/// The usual case: counted, nothing to announce.
final class GoalUnchanged extends GoalEvent {
  const GoalUnchanged();
}

/// Today's goal was met on this card.
final class GoalReached extends GoalEvent {
  const GoalReached(this.points);

  /// Points just awarded, which is also the size of the goal that was met.
  final int points;
}

/// Today's goal was met and it paid for a new rank.
final class RankReached extends GoalEvent {
  const RankReached(this.points, this.rank);

  final int points;
  final Rank rank;
}
