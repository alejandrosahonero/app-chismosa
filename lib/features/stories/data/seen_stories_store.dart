import 'package:chismosa/services/storage/key_value_store.dart';

/// Ids of the cards this device has already dealt.
///
/// **On the device and not in Postgres.** A row per (reader, story) grows as
/// users x catalogue, and that one table would eat the 500 MB of the free plan
/// long before anything else did. The cost of keeping it local is that a
/// reinstall without a backup deals some old cards again — which is a far
/// smaller problem than a feed that stops working.
///
/// Ordered, oldest first, because only the newest slice is worth sending to the
/// server as an exclusion hint.
class SeenStoriesStore {
  const SeenStoriesStore(this._store);

  static const String _key = 'stories_seen_ids';

  /// Hard cap on what is kept.
  ///
  /// `SharedPreferences` is loaded whole at startup (§10), so this list is on
  /// the first-frame path: at 36 characters per uuid, two thousand ids is about
  /// 70 kB, which is the most a launch should ever spend on "cards I already
  /// read". Past that the oldest are dropped, and the worst that can happen is
  /// a card from months ago coming back up.
  static const int maxEntries = 2000;

  final KeyValueStore _store;

  List<String> read() => _store.getStringList(_key);

  /// Appends [ids], keeping the order and dropping duplicates and overflow.
  ///
  /// Returns what was stored so a caller holding the list in memory does not
  /// have to read it back.
  Future<List<String>> add(Iterable<String> ids) async {
    final List<String> current = read();
    final Set<String> known = current.toSet();
    final List<String> added = ids.where(known.add).toList(growable: false);
    if (added.isEmpty) return current;

    final List<String> merged = <String>[...current, ...added];
    final List<String> capped = merged.length <= maxEntries
        ? merged
        : merged.sublist(merged.length - maxEntries);

    await _store.setStringList(_key, capped);
    return capped;
  }

  /// Forgets everything. Only reachable from the "start over" action: a reader
  /// who has run out of stories is asking to be dealt them again.
  Future<void> clear() => _store.remove(_key);
}
