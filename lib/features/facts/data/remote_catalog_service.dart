import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aja/core/config/remote_catalog_config.dart';
import 'package:aja/core/utils/app_logger.dart';
import 'package:aja/features/facts/domain/remote_catalogue.dart';
import 'package:aja/services/storage/key_value_store.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Downloads and caches the catalogue published after the app shipped.
///
/// The rule this service exists to enforce: **the network can only ever add**.
/// A dead connection, a 404, a truncated body or a file full of typos all end
/// the same way — the app runs on what it already had. There is no state in
/// which a bad download leaves the user with fewer questions than the APK
/// carries.
///
/// The download is never awaited by the UI. It runs after the first frame and
/// writes to disk; the merged result is picked up on the **next** launch. That
/// is on purpose: swapping the catalogue under somebody who is mid-deck would
/// move the cards they are reading.
class RemoteCatalogService {
  RemoteCatalogService(
    this._store, {
    http.Client? client,
    Future<Directory> Function()? directory,
  }) : _client = client ?? http.Client(),
       _directory = directory ?? getApplicationSupportDirectory;

  final KeyValueStore _store;
  final http.Client _client;

  /// Injected so the cache can be pointed at a temp folder in tests.
  final Future<Directory> Function() _directory;

  static const String _etagKey = 'remote_catalog_etag';
  static const String _versionKey = 'remote_catalog_version';
  static const String _fetchedAtKey = 'remote_catalog_fetched_at';

  void dispose() => _client.close();

  /// Version currently on disk. 0 when nothing has been downloaded.
  int get cachedVersion => _store.getInt(_versionKey);

  DateTime? get lastFetchedAt => _store.getDateTime(_fetchedAtKey);

  /// Reads the cached catalogue, or null when there is none or it is unusable.
  Future<RemoteCatalogue?> readCache() async {
    if (!RemoteCatalogConfig.isConfigured) return null;

    try {
      final File file = await _cacheFile();
      if (!file.existsSync()) return null;

      return await compute(parseRemoteCatalogue, await file.readAsString());
    } on Object catch (error) {
      // A cache we cannot read is a cache we should not keep.
      AppLogger.debug('Remote catalogue cache unreadable: $error', name: 'cat');
      unawaited(_deleteCache());
      return null;
    }
  }

  /// Fetches the published catalogue and caches it if it is newer.
  ///
  /// Never throws: every failure path degrades to "keep what we have".
  Future<void> refresh() async {
    if (!RemoteCatalogConfig.isConfigured) return;

    try {
      final String? etag = _store.getString(_etagKey);

      final http.Response response = await _client
          .get(
            Uri.parse(RemoteCatalogConfig.url),
            // The cheapest possible no-op: an unchanged catalogue costs one
            // 304 and no parsing at all.
            headers: <String, String>{'If-None-Match': ?etag},
          )
          .timeout(RemoteCatalogConfig.requestTimeout);

      if (response.statusCode == HttpStatus.notModified) return;

      if (response.statusCode != HttpStatus.ok) {
        AppLogger.debug(
          'Remote catalogue HTTP ${response.statusCode}',
          name: 'cat',
        );
        return;
      }

      if (response.bodyBytes.length > RemoteCatalogConfig.maxPayloadBytes) {
        AppLogger.error(
          'Remote catalogue too large, ignored',
          error: response.bodyBytes.length,
        );
        return;
      }

      // Decoded explicitly as UTF-8: the questions are full of accents and a
      // host that omits the charset would otherwise mangle every one of them.
      final String raw = utf8.decode(response.bodyBytes);
      final RemoteCatalogue catalogue = await compute(
        parseRemoteCatalogue,
        raw,
      );

      if (catalogue.version < cachedVersion) {
        AppLogger.debug(
          'Remote catalogue v${catalogue.version} older than cached '
          'v$cachedVersion, ignored',
          name: 'cat',
        );
        return;
      }

      if (catalogue.skipped > 0) {
        AppLogger.error(
          'Remote catalogue dropped ${catalogue.skipped} malformed entries',
        );
      }

      // Written only after it has parsed: the file on disk is always a
      // catalogue that has already been proven readable.
      await (await _cacheFile()).writeAsString(raw, flush: true);
      await _store.setInt(_versionKey, catalogue.version);
      await _store.setDateTime(_fetchedAtKey, DateTime.now().toUtc());

      final String? received = response.headers['etag'];
      if (received != null) await _store.setString(_etagKey, received);

      AppLogger.debug(
        'Remote catalogue v${catalogue.version}: '
        '${catalogue.facts.length} facts, ${catalogue.removed.length} removed',
        name: 'cat',
      );
    } on Object catch (error) {
      AppLogger.debug('Remote catalogue refresh failed: $error', name: 'cat');
    }
  }

  Future<File> _cacheFile() async =>
      File('${(await _directory()).path}/${RemoteCatalogConfig.cacheFileName}');

  Future<void> _deleteCache() async {
    try {
      final File file = await _cacheFile();
      if (file.existsSync()) await file.delete();
      await _store.remove(_etagKey);
      await _store.remove(_versionKey);
    } on Object catch (error) {
      AppLogger.debug('Could not drop catalogue cache: $error', name: 'cat');
    }
  }
}
