/// The rank ladder: thresholds, what comes next, and how the bar fills.
library;

import 'package:aja/features/goals/domain/rank.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Rank.forPoints', () {
    test('starts everybody at the bottom', () {
      expect(Rank.forPoints(0), Rank.curious);
      expect(Rank.forPoints(-10), Rank.curious);
    });

    test('promotes exactly on the threshold, not one point later', () {
      for (final Rank rank in Rank.values) {
        expect(Rank.forPoints(rank.minPoints), rank);
        if (rank != Rank.curious) {
          expect(Rank.forPoints(rank.minPoints - 1), isNot(rank));
        }
      }
    });

    test('holds the top rank however many points pile up after it', () {
      expect(Rank.forPoints(Rank.oracle.minPoints * 10), Rank.oracle);
    });

    test('the ladder only ever climbs', () {
      for (int i = 1; i < Rank.values.length; i++) {
        expect(
          Rank.values[i].minPoints,
          greaterThan(Rank.values[i - 1].minPoints),
        );
      }
    });
  });

  group('Rank.next and pointsTo', () {
    test('the top of the ladder has nothing above it', () {
      expect(Rank.oracle.next, isNull);
      expect(Rank.oracle.pointsTo(Rank.oracle.minPoints), isNull);
    });

    test('counts down the points still owed', () {
      expect(Rank.curious.pointsTo(0), Rank.inquisitive.minPoints);
      expect(Rank.curious.pointsTo(50), Rank.inquisitive.minPoints - 50);
    });

    test('never reports a negative debt', () {
      expect(Rank.curious.pointsTo(Rank.inquisitive.minPoints + 100), 0);
    });
  });

  group('Rank.progressTo', () {
    test('measures across the current band, not from zero', () {
      // Half way between 60 and 180 is 120, and the bar must read 50% there —
      // a bar measured from zero would show 67% and creep forward even on days
      // that earned nothing towards the next rank.
      final int middle =
          (Rank.inquisitive.minPoints + Rank.knowItAll.minPoints) ~/ 2;
      expect(Rank.inquisitive.progressTo(middle), closeTo(0.5, 0.01));
    });

    test('is empty on arrival and full on departure', () {
      expect(Rank.inquisitive.progressTo(Rank.inquisitive.minPoints), 0);
      expect(Rank.inquisitive.progressTo(Rank.knowItAll.minPoints), 1);
    });

    test('is full at the top of the ladder', () {
      expect(Rank.oracle.progressTo(Rank.oracle.minPoints), 1);
    });
  });
}
