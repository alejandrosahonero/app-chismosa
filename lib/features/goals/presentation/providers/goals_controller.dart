import 'dart:async';

import 'package:aja/features/goals/domain/daily_goal.dart';
import 'package:aja/features/goals/domain/goals_state.dart';
import 'package:aja/features/goals/domain/rank.dart';
import 'package:aja/services/storage/key_value_store.dart';
import 'package:aja/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The clock the goal reads.
///
/// A provider rather than a field so tests can override it in the scope and
/// still get a controller built against the fake day. Lives here because the
/// goal is the only thing in the app that cares what day it is.
final Provider<DateTime Function()> goalsClockProvider =
    Provider<DateTime Function()>((Ref ref) => DateTime.now);

final NotifierProvider<GoalsController, GoalsState> goalsControllerProvider =
    NotifierProvider<GoalsController, GoalsState>(GoalsController.new);

/// Owns the daily goal and the points behind the ranks.
///
/// Synchronous: preferences are already loaded by the time the tree is built,
/// so the ring never flashes an empty state on the first frame.
///
/// **Learning a fact means flipping the card and reading the answer.** Not
/// swiping past it — the deck would count as "learned" everything a fast
/// scroller skipped, and a goal that fills itself is not a goal. It is the same
/// moment the review prompt hangs off, for the same reason: it is the only
/// thing the user actually came here to do.
class GoalsController extends Notifier<GoalsState> {
  static const String _dayKey = 'goals_day';
  static const String _learnedKey = 'goals_learned_today';
  static const String _pointsKey = 'goals_points';
  static const String _awardedKey = 'goals_awarded';
  static const String _firstDayKey = 'goals_first_day';

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  int get _today => DailyGoal.epochDayOf(ref.read(goalsClockProvider)());

  @override
  GoalsState build() => _readFor(_today);

  /// The day the user first met the feature, recorded the first time it is
  /// asked for.
  ///
  /// The write is fire-and-forget: the value is returned synchronously either
  /// way, and the worst case of losing it is one extra gentle day.
  int _firstDay(int today) {
    final int stored = _store.getInt(_firstDayKey, fallback: -1);
    if (stored >= 0) return stored;

    unawaited(_store.setInt(_firstDayKey, today));
    return today;
  }

  /// Reads storage as of [today], applying the day rollover.
  ///
  /// Yesterday's counters are never trusted: the stored day is compared with
  /// the clock on every read, so a stale `awarded` flag cannot leak into a new
  /// day even though nothing is erased until the next write.
  GoalsState _readFor(int today) {
    final KeyValueStore store = _store;
    final bool isToday = store.getInt(_dayKey, fallback: today) == today;

    return GoalsState(
      epochDay: today,
      target: DailyGoal.targetFor(today, firstDay: _firstDay(today)),
      learned: isToday ? store.getStringList(_learnedKey).length : 0,
      points: store.getInt(_pointsKey),
      awarded: isToday && store.getBool(_awardedKey),
    );
  }

  /// Counts one fact as learned and returns whether that was worth announcing.
  ///
  /// Deliberately derived from storage rather than from [state]: an app left
  /// open across midnight still holds yesterday's state in memory, and this is
  /// the first thing that happens on the new day, so it is where the rollover
  /// has to be caught.
  ///
  /// The same fact only counts once a day. Flipping a card back and forth, or
  /// re-reading a favourite, must not fill the ring — but a card met again
  /// tomorrow does count, otherwise restarting the deck would leave a long-time
  /// user with a goal they can no longer reach.
  Future<GoalEvent> registerLearned(String factId) async {
    final KeyValueStore store = _store;
    final int today = _today;
    final bool isToday = store.getInt(_dayKey, fallback: today) == today;

    final List<String> learned = isToday
        ? List<String>.of(store.getStringList(_learnedKey))
        : <String>[];

    if (learned.contains(factId)) return const GoalUnchanged();
    learned.add(factId);

    final int target = DailyGoal.targetFor(today, firstDay: _firstDay(today));
    final int pointsBefore = store.getInt(_pointsKey);
    bool awarded = isToday && store.getBool(_awardedKey);

    int points = pointsBefore;
    GoalEvent event = const GoalUnchanged();

    if (!awarded && learned.length >= target) {
      // The day pays what it asked for: a 15-fact day is worth more than an
      // 8-fact one, which needs no invented constant to be fair.
      points += target;
      awarded = true;

      final Rank climbed = Rank.forPoints(points);
      event = climbed == Rank.forPoints(pointsBefore)
          ? GoalReached(target)
          : RankReached(target, climbed);
    }

    await store.setInt(_dayKey, today);
    await store.setStringList(_learnedKey, learned);
    await store.setBool(_awardedKey, value: awarded);
    if (points != pointsBefore) await store.setInt(_pointsKey, points);

    state = GoalsState(
      epochDay: today,
      target: target,
      learned: learned.length,
      points: points,
      awarded: awarded,
    );

    return event;
  }

  /// Re-reads the clock. For the app coming back from the background onto a new
  /// day, where nothing has been learned yet and the ring would otherwise keep
  /// showing yesterday until the first flip.
  void refresh() => state = _readFor(_today);
}
