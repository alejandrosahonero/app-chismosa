/// How many facts today asks for, and what "today" even means.
///
/// Pure functions with no storage and no clock of their own: the goal is a
/// function of the date, so it can be tested by passing a day number and — the
/// part that matters — it cannot be re-rolled by closing and reopening the app.
abstract final class DailyGoal {
  /// The goals the app rotates through.
  ///
  /// Short enough that the smallest is a two-minute session and the largest
  /// still fits in one sitting. A goal nobody finishes is a goal that teaches
  /// the user to ignore the ring.
  static const List<int> sizes = <int>[8, 10, 12, 15];

  /// The one used on the install day: always the smallest.
  ///
  /// A first session that ends on a completed goal is what sells the whole
  /// system, and opening a fresh install on 15 is a coin flip on whether that
  /// happens.
  static int get gentle => sizes.reduce((int a, int b) => a < b ? a : b);

  /// Calendar day index, derived from the **local** date.
  ///
  /// The local Y/M/D is deliberately re-read as UTC before being turned into a
  /// number. Taking the local timestamp directly would make the index move by
  /// something other than one across a DST change in a UTC±0 timezone, handing
  /// the user the same day twice or skipping one. This way the number is the
  /// calendar date and moves by exactly one at every local midnight.
  static int epochDayOf(DateTime now) =>
      DateTime.utc(now.year, now.month, now.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;

  /// Today's goal.
  ///
  /// [firstDay] is the day the user met the feature; on it and anything before
  /// it the goal is [gentle].
  ///
  /// Days are dealt in blocks of [sizes]`.length`, each block a shuffle of the
  /// sizes, so every size comes up exactly once every four days rather than
  /// merely often. Two adjacent days can therefore only collide across a block
  /// boundary, and [_orderFor] rules that out.
  static int targetFor(int epochDay, {required int firstDay}) {
    if (epochDay <= firstDay) return gentle;

    final int slot = _slotOf(epochDay);
    final List<int> order = _orderFor(_blockOf(epochDay, slot));

    // The day after the install day is the one case the block scheme cannot
    // see: its neighbour is not a dealt day at all, it is the forced [gentle].
    // Borrowing the slot *behind* it is free — that slot belongs either to the
    // install day itself, which ignores it, or to a day three places away.
    if (epochDay == firstDay + 1 && order[slot] == gentle) {
      return order[(slot + sizes.length - 1) % sizes.length];
    }

    return order[slot];
  }

  static int _slotOf(int epochDay) => epochDay % sizes.length;

  /// Floor division, written out: `~/` truncates towards zero, which would put
  /// two consecutive pre-1970 days in different blocks.
  static int _blockOf(int epochDay, int slot) =>
      (epochDay - slot) ~/ sizes.length;

  /// One block's worth of goals: every size, in an order derived from the block
  /// number.
  ///
  /// The first entry is checked against the last entry of the previous block so
  /// a boundary cannot repeat a number. The fix swaps entries 0 and 1 and never
  /// touches the last one — which is what keeps this from turning into a chain:
  /// the next block reads a value that no fix can have moved, so no block ever
  /// has to resolve its predecessor before it can resolve itself.
  static List<int> _orderFor(int block) {
    final List<int> order = _shuffle(block);
    final int previousLast = _shuffle(block - 1).last;

    if (order.first == previousLast) {
      final int first = order[0];
      order[0] = order[1];
      order[1] = first;
    }

    return order;
  }

  /// Deterministic Fisher-Yates over [sizes], seeded by the block number.
  static List<int> _shuffle(int block) {
    final List<int> order = List<int>.of(sizes);
    int seed = _mix(block);

    for (int i = order.length - 1; i > 0; i--) {
      seed = _mix(seed);
      final int j = seed % (i + 1);
      final int swapped = order[i];
      order[i] = order[j];
      order[j] = swapped;
    }

    return order;
  }

  /// Integer hash (a 64-bit take on the murmur finalizer).
  ///
  /// Hand-rolled instead of `Random(seed)`: nothing about the sequence is
  /// stored — yesterday's goal is recomputed, never saved — so it has to keep
  /// producing the same answer across Dart releases, and `Random`'s algorithm
  /// is not part of its contract.
  static int _mix(int value) {
    int hash = value * 0x27d4eb2d;
    hash ^= hash >>> 15;
    hash *= 0x85ebca6b;
    hash ^= hash >>> 13;
    return hash & 0x7fffffff;
  }
}
