/// The ladder the points climb.
///
/// Thresholds are in points, and a met goal pays exactly what the day asked
/// for, so a day is worth 8–15. That puts the second rank inside the first
/// week — early enough to show the user the system works — and the last one out
/// past a hundred completed days, which is where a top rank belongs.
///
/// Flutter-free on purpose, like `FactCategory`: the name and the icon are a
/// presentation concern and live in `rank_style.dart`.
enum Rank {
  curious(0),
  inquisitive(60),
  knowItAll(180),
  scholar(400),
  encyclopedia(800),
  oracle(1400);

  const Rank(this.minPoints);

  /// Points needed to hold this rank.
  final int minPoints;

  /// The highest rank [points] has paid for.
  static Rank forPoints(int points) {
    Rank held = Rank.values.first;
    for (final Rank rank in Rank.values) {
      if (points >= rank.minPoints) held = rank;
    }
    return held;
  }

  /// The next one up, or null at the top of the ladder.
  Rank? get next =>
      index + 1 < Rank.values.length ? Rank.values[index + 1] : null;

  /// Points still owed for [next], or null once there is nothing left to climb.
  int? pointsTo(int points) {
    final Rank? target = next;
    return target == null
        ? null
        : (target.minPoints - points).clamp(0, target.minPoints);
  }

  /// 0→1 across the current band, for the bar on the progress screen.
  ///
  /// Measured from this rank's floor rather than from zero: a bar that fills
  /// once for the whole game would sit at 4% for a month.
  double progressTo(int points) {
    final Rank? target = next;
    if (target == null) return 1;

    final int band = target.minPoints - minPoints;
    if (band <= 0) return 1;

    return ((points - minPoints) / band).clamp(0.0, 1.0);
  }
}
