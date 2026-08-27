import 'dart:convert';

import 'package:aja/core/errors/app_exception.dart';
import 'package:aja/core/utils/app_logger.dart';
import 'package:aja/features/facts/domain/fact.dart';
import 'package:aja/features/facts/domain/remote_catalogue.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Parses the catalogue. Top level on purpose: [compute] can only run a
/// function that is not a closure.
@visibleForTesting
List<Fact> parseFacts(String raw) {
  final Map<String, dynamic> root = jsonDecode(raw) as Map<String, dynamic>;
  final List<dynamic> entries = root['facts']! as List<dynamic>;

  return List<Fact>.unmodifiable(
    entries.map(
      (dynamic entry) => Fact.fromJson(entry as Map<String, dynamic>),
    ),
  );
}

/// Reads the question catalogue: the bundled asset, plus whatever has been
/// published since the app shipped.
///
/// The JSON inside the APK is the floor and it is always enough on its own — it
/// loads instantly, works offline and cannot fail. On top of it goes the last
/// catalogue downloaded by `RemoteCatalogService`, which corrects, removes and
/// adds ([mergeCatalogues]). The overlay is read from disk, never from the
/// network: this call is on the path to the first screen and must not wait on a
/// request.
///
/// Parsing runs on a background isolate through [compute] because the catalogue
/// is meant to grow to hundreds of entries and this load happens while the
/// first screen is being painted.
///
/// The result is cached for the process lifetime. That is also what pins the
/// content for the session: a download that lands mid-session is written to
/// disk and picked up on the next launch, instead of moving the cards under
/// somebody who is reading them.
class FactRepository {
  FactRepository({AssetBundle? bundle, this.overlay})
    : _bundle = bundle ?? rootBundle;

  static const String assetPath = 'assets/data/facts.json';

  final AssetBundle _bundle;

  /// Null disables the remote layer entirely, which is what tests and a build
  /// without a configured URL both want.
  final ReadRemoteCatalogue? overlay;

  List<Fact>? _cache;

  Future<List<Fact>> loadAll() async {
    final List<Fact>? cached = _cache;
    if (cached != null) return cached;

    late final List<Fact> bundled;
    try {
      final String raw = await _bundle.loadString(assetPath);
      bundled = await compute(parseFacts, raw);
      if (bundled.isEmpty) {
        throw const DataException('The fact catalogue is empty');
      }
    } on AppException {
      rethrow;
    } on Object catch (error) {
      throw DataException('Could not read the fact catalogue', cause: error);
    }

    // Separate try: a broken overlay must cost the user nothing, so it falls
    // back to the bundled catalogue instead of taking the app down with it.
    try {
      final RemoteCatalogue? published = await overlay?.call();
      return _cache = mergeCatalogues(bundled, published);
    } on Object catch (error) {
      AppLogger.error('Remote catalogue ignored', error: error);
      return _cache = bundled;
    }
  }
}

/// Reads the catalogue cached on disk. Implemented by `RemoteCatalogService`.
typedef ReadRemoteCatalogue = Future<RemoteCatalogue?> Function();
