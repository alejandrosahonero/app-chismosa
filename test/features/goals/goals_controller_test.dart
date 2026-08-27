/// The controller that turns flipped cards into points.
///
/// Two things here are worth more than the rest: the goal pays **once** a day,
/// and the day rolls over from the clock rather than from whatever was in
/// memory when the app was last opened. Both are the kind of bug you only find
/// in production, at midnight, on somebody else's phone.

library;

import 'package:aja/features/goals/domain/daily_goal.dart';
import 'package:aja/features/goals/domain/goals_state.dart';
import 'package:aja/features/goals/domain/rank.dart';
import 'package:aja/features/goals/presentation/providers/goals_controller.dart';
import 'package:aja/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  /// A day that is not the install day, so the goal is the rotating one rather
  /// than the gentle first-run size.
  final DateTime day1 = DateTime(2026, 5, 20, 21);
  final DateTime day2 = DateTime(2026, 5, 21, 9);

  late DateTime now;
  late ProviderContainer container;

  /// Everything the feature persists, so a test can start mid-history.
  Future<ProviderContainer> boot(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final ProviderContainer built = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        goalsClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(built.dispose);
    return built;
  }

  GoalsController controller() =>
      container.read(goalsControllerProvider.notifier);

  GoalsState goals() => container.read(goalsControllerProvider);

  /// Flips [count] distinct cards, returning the last thing that happened.
  Future<GoalEvent> learn(int count, {int from = 0}) async {
    GoalEvent event = const GoalUnchanged();
    for (int i = 0; i < count; i++) {
      event = await controller().registerLearned('fact-${from + i}');
    }
    return event;
  }

  setUp(() async {
    now = day1;
    // An install day in the past, so `day1` gets a rotating goal.
    container = await boot(<String, Object>{
      'goals_first_day': DailyGoal.epochDayOf(day1) - 30,
    });
  });

  test('a fresh day starts empty, with today\'s goal already known', () {
    expect(goals().learned, 0);
    expect(goals().points, 0);
    expect(goals().awarded, isFalse);
    expect(goals().isComplete, isFalse);
    expect(DailyGoal.sizes, contains(goals().target));
    expect(goals().rank, Rank.curious);
  });

  test('flipping a card counts it', () async {
    await learn(1);
    expect(goals().learned, 1);
    expect(goals().remaining, goals().target - 1);
  });

  test('the same card cannot be counted twice in one day', () async {
    await controller().registerLearned('fact-0');
    final GoalEvent again = await controller().registerLearned('fact-0');

    expect(goals().learned, 1);
    expect(again, isA<GoalUnchanged>());
  });

  test('nothing is announced before the goal is met', () async {
    final GoalEvent event = await learn(goals().target - 1);

    expect(event, isA<GoalUnchanged>());
    expect(goals().isComplete, isFalse);
    expect(goals().points, 0);
  });

  test('meeting the goal pays exactly what the day asked for', () async {
    final int target = goals().target;
    final GoalEvent event = await learn(target);

    expect(event, isA<GoalReached>());
    expect((event as GoalReached).points, target);
    expect(goals().points, target);
    expect(goals().awarded, isTrue);
    expect(goals().isComplete, isTrue);
  });

  test('reading past the goal keeps counting but stops paying', () async {
    final int target = goals().target;
    await learn(target);

    final GoalEvent extra = await learn(3, from: target);

    expect(extra, isA<GoalUnchanged>());
    expect(goals().points, target, reason: 'the day must only pay once');
    expect(goals().learned, target + 3);
    // The ring is full, not overflowing.
    expect(goals().progress, 1);
    expect(goals().remaining, 0);
  });

  test('crossing a threshold announces the new rank', () async {
    now = day1;
    container = await boot(<String, Object>{
      'goals_first_day': DailyGoal.epochDayOf(day1) - 30,
      // One point short of the second rank, so any goal size crosses it.
      'goals_points': Rank.inquisitive.minPoints - 1,
    });

    expect(goals().rank, Rank.curious);

    final GoalEvent event = await learn(goals().target);

    expect(event, isA<RankReached>());
    expect((event as RankReached).rank, Rank.inquisitive);
    expect(goals().rank, Rank.inquisitive);
  });

  test(
    'a goal met without changing rank does not interrupt the user',
    () async {
      final GoalEvent event = await learn(goals().target);

      // Rank one starts at zero points, so the very first goal cannot promote.
      expect(event, isA<GoalReached>());
      expect(event, isNot(isA<RankReached>()));
    },
  );

  group('the day rollover', () {
    test('resets the count and lets a new goal be paid', () async {
      final int day1Target = goals().target;
      await learn(day1Target);
      expect(goals().points, day1Target);

      now = day2;
      // The first flip of the new day is what catches the rollover: the state
      // in memory still believes it is yesterday until something happens.
      await controller().registerLearned('fact-0');

      expect(
        goals().learned,
        1,
        reason: 'yesterday\'s pile must not carry over',
      );
      expect(goals().awarded, isFalse, reason: 'the new day owes its own goal');
      expect(goals().points, day1Target, reason: 'points are for keeps');

      final int day2Target = goals().target;
      final GoalEvent event = await learn(day2Target - 1, from: 1);

      expect(event, isA<GoalReached>());
      expect(goals().points, day1Target + day2Target);
    });

    test('a card learned yesterday counts again today', () async {
      await controller().registerLearned('fact-0');

      now = day2;
      final GoalEvent again = await controller().registerLearned('fact-0');

      expect(again, isA<GoalUnchanged>());
      expect(
        goals().learned,
        1,
        reason: 'it counted, it just did not finish the goal',
      );
    });

    test('refresh picks up the new day with nothing learned yet', () async {
      await learn(2);
      now = day2;

      controller().refresh();

      expect(goals().learned, 0);
      expect(goals().awarded, isFalse);
    });

    test('yesterday\'s payout cannot leak into a fresh launch', () async {
      final int day1Target = goals().target;
      await learn(day1Target);

      // A new process on the following day, reading the same preferences.
      now = day2;
      container = await boot(
        Map<String, Object>.from(<String, Object>{
          'goals_first_day': DailyGoal.epochDayOf(day1) - 30,
          'goals_day': DailyGoal.epochDayOf(day1),
          'goals_learned_today': <String>[
            for (int i = 0; i < day1Target; i++) 'fact-$i',
          ],
          'goals_awarded': true,
          'goals_points': day1Target,
        }),
      );

      expect(goals().learned, 0);
      expect(goals().awarded, isFalse);
      expect(goals().points, day1Target);
    });
  });

  test('points and progress survive a restart', () async {
    final int target = goals().target;
    await learn(target - 1);

    final int day = DailyGoal.epochDayOf(day1);
    container = await boot(<String, Object>{
      'goals_first_day': day - 30,
      'goals_day': day,
      'goals_learned_today': <String>[
        for (int i = 0; i < target - 1; i++) 'fact-$i',
      ],
      'goals_points': 0,
    });

    expect(goals().learned, target - 1);
    expect(goals().target, target);

    // And the last card still finishes the job it was one short of.
    final GoalEvent event = await controller().registerLearned('fact-last');
    expect(event, isA<GoalReached>());
  });

  test('the install day is a gentle one', () async {
    now = day1;
    container = await boot(<String, Object>{});

    expect(goals().target, DailyGoal.gentle);
  });
}
