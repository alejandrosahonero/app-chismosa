import 'dart:convert';

import 'package:aja/features/facts/domain/fact.dart';
import 'package:flutter/foundation.dart';

/// A catalogue downloaded after the app shipped.
///
/// Same shape as the bundled asset plus two fields, so the two files are
/// interchangeable and one set of tooling works on both.
@immutable
class RemoteCatalogue {
  const RemoteCatalogue({
    required this.version,
    required this.facts,
    required this.removed,
    this.skipped = 0,
  });

  /// Monotonic. A payload whose version is lower than the one already cached is
  /// refused: that is a stale CDN copy or a bad rollback, not an update.
  final int version;

  final List<Fact> facts;

  /// Ids to delete from the bundled catalogue.
  ///
  /// This is the whole reason the remote layer is worth having on day one: the
  /// 87 shipped facts carry unverified sources, and when one of them turns out
  /// to be wrong it has to be killable **today**, not in the next release.
  final List<String> removed;

  /// Entries that failed to parse and were dropped. Reported, never fatal.
  final int skipped;

  bool get isEmpty => facts.isEmpty && removed.isEmpty;
}

/// Parses a downloaded catalogue. Top level so it can run through [compute].
///
/// **Tolerant by design, unlike the bundled parser.** A bad category id in the
/// asset is a build-time bug and must explode; the same mistake in a file
/// served over the network would brick every installed copy of the app at
/// once. So a malformed entry is dropped and counted, and the rest is kept.
/// Only a payload that is not a catalogue at all is rejected outright.
RemoteCatalogue parseRemoteCatalogue(String raw) {
  final Object? decoded = jsonDecode(raw);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Remote catalogue is not an object');
  }

  final Object? version = decoded['version'];
  if (version is! int) {
    throw const FormatException('Remote catalogue has no integer version');
  }

  final Object? entries = decoded['facts'] ?? const <dynamic>[];
  if (entries is! List<dynamic>) {
    throw const FormatException('Remote catalogue "facts" is not a list');
  }

  final List<Fact> facts = <Fact>[];
  int skipped = 0;

  for (final dynamic entry in entries) {
    try {
      facts.add(Fact.fromJson(entry as Map<String, dynamic>));
    } on Object {
      // One broken question must not cost the user the other four hundred.
      skipped++;
    }
  }

  final Object? removed = decoded['removed'] ?? const <dynamic>[];
  final List<String> removedIds = removed is List<dynamic>
      ? removed.whereType<String>().toList(growable: false)
      : const <String>[];

  return RemoteCatalogue(
    version: version,
    facts: List<Fact>.unmodifiable(facts),
    removed: removedIds,
    skipped: skipped,
  );
}

/// Folds a downloaded catalogue over the bundled one.
///
/// Rules, in order:
///
/// 1. **Same id replaces.** That is how a wrong answer or a missing source gets
///    corrected without a release.
/// 2. **Listed in `removed` disappears.**
/// 3. **New ids are appended**, in the order the remote file lists them.
///
/// Appending rather than interleaving is deliberate: the bundled order is
/// hand-curated and the user's saved progress is a *count* of cards read, so
/// adding at the end leaves everybody exactly where they were. Keep the remote
/// file interleaved by category the same way the asset is — see §3.2.
List<Fact> mergeCatalogues(List<Fact> bundled, RemoteCatalogue? overlay) {
  if (overlay == null || overlay.isEmpty) return bundled;

  final Map<String, Fact> replacements = <String, Fact>{
    for (final Fact fact in overlay.facts) fact.id: fact,
  };
  final Set<String> removed = overlay.removed.toSet();

  final List<Fact> merged = <Fact>[];
  final Set<String> kept = <String>{};

  for (final Fact fact in bundled) {
    if (removed.contains(fact.id)) continue;
    merged.add(replacements[fact.id] ?? fact);
    kept.add(fact.id);
  }

  for (final Fact fact in overlay.facts) {
    if (kept.contains(fact.id) || removed.contains(fact.id)) continue;
    merged.add(fact);
  }

  // A remote file that empties the catalogue is a mistake, never an intention:
  // an app with no cards is worse than an app with stale ones.
  if (merged.isEmpty) return bundled;

  return List<Fact>.unmodifiable(merged);
}
