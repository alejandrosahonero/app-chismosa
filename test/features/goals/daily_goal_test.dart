/// The goal is a function of the date and nothing else.
///
/// That is the whole security model of the feature: there is no server, so the
/// only thing stopping a user from re-rolling an inconvenient goal is that
/// closing the app cannot change the answer. These tests pin that down, plus
/// the two properties the goal is supposed to have — it moves day to day, and
/// the first day is winnable.

library;

import 'package:aja/features/goals/domain/daily_goal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DailyGoal.epochDayOf', () {
    test('is the calendar date, not the time of day', () {
      expect(
        DailyGoal.epochDayOf(DateTime(2026, 3, 29)),
        DailyGoal.epochDayOf(DateTime(2026, 3, 29, 23, 59, 59)),
      );
    });

    test('advances by exactly one across the European DST change', () {
      // 29 March 2026 is when the EU springs forward. A day index taken from
      // the local timestamp instead of the calendar date can repeat or skip
      // here, which would hand the user the same goal twice.
      expect(
        DailyGoal.epochDayOf(DateTime(2026, 3, 29, 12)) -
            DailyGoal.epochDayOf(DateTime(2026, 3, 28, 12)),
        1,
      );
      expect(
        DailyGoal.epochDayOf(DateTime(2026, 3, 30, 12)) -
            DailyGoal.epochDayOf(DateTime(2026, 3, 29, 12)),
        1,
      );
    });

    test('advances by one across month and year boundaries', () {
      expect(
        DailyGoal.epochDayOf(DateTime(2026, 1, 1)) -
            DailyGoal.epochDayOf(DateTime(2025, 12, 31)),
        1,
      );
      expect(
        DailyGoal.epochDayOf(DateTime(2024, 3, 1)) -
            DailyGoal.epochDayOf(DateTime(2024, 2, 29)),
        1,
      );
    });
  });

  group('DailyGoal.targetFor', () {
    const int firstDay = 20000;

    test('gives the same answer every time it is asked', () {
      for (int day = firstDay; day < firstDay + 50; day++) {
        expect(
          DailyGoal.targetFor(day, firstDay: firstDay),
          DailyGoal.targetFor(day, firstDay: firstDay),
        );
      }
    });

    test('is gentle on the install day and before it', () {
      expect(
        DailyGoal.targetFor(firstDay, firstDay: firstDay),
        DailyGoal.gentle,
      );
      expect(
        DailyGoal.targetFor(firstDay - 5, firstDay: firstDay),
        DailyGoal.gentle,
      );
      expect(
        DailyGoal.gentle,
        DailyGoal.sizes.reduce((int a, int b) => a < b ? a : b),
      );
    });

    test('only ever offers one of the published sizes', () {
      for (int day = firstDay; day < firstDay + 2000; day++) {
        expect(
          DailyGoal.sizes,
          contains(DailyGoal.targetFor(day, firstDay: firstDay)),
        );
      }
    });

    test('never repeats the same number two days running', () {
      for (int day = firstDay + 1; day < firstDay + 2000; day++) {
        expect(
          DailyGoal.targetFor(day, firstDay: firstDay),
          isNot(DailyGoal.targetFor(day - 1, firstDay: firstDay)),
          reason: 'day $day repeated the previous goal',
        );
      }
    });

    test('uses every size, none of them rarely', () {
      final Map<int, int> seen = <int, int>{
        for (final int size in DailyGoal.sizes) size: 0,
      };
      const int days = 2000;

      for (int day = firstDay + 1; day <= firstDay + days; day++) {
        seen[DailyGoal.targetFor(day, firstDay: firstDay)] =
            seen[DailyGoal.targetFor(day, firstDay: firstDay)]! + 1;
      }

      for (final MapEntry<int, int> entry in seen.entries) {
        // A perfectly even split would be 25%. Anything under 15% would mean
        // one of the sizes is decorative.
        expect(
          entry.value / days,
          greaterThan(0.15),
          reason: 'goal ${entry.key} almost never comes up',
        );
      }
    });
  });
}
