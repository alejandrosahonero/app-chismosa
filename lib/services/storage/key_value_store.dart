import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper over [SharedPreferences] for non sensitive flags and counters.
///
/// Features depend on this instead of the plugin so the backing store can be
/// swapped (and faked in tests) without touching feature code. Anything
/// sensitive — purchase tokens, entitlements — belongs in `SecureStore`.
class KeyValueStore {
  const KeyValueStore(this._prefs);

  final SharedPreferences _prefs;

  int getInt(String key, {int fallback = 0}) => _prefs.getInt(key) ?? fallback;

  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);

  bool getBool(String key, {bool fallback = false}) =>
      _prefs.getBool(key) ?? fallback;

  Future<void> setBool(String key, {required bool value}) =>
      _prefs.setBool(key, value);

  String? getString(String key) => _prefs.getString(key);

  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  /// Returns an empty list rather than null: every call site wants to iterate,
  /// and none of them cares about the difference between "never written" and
  /// "written empty".
  List<String> getStringList(String key) =>
      _prefs.getStringList(key) ?? const <String>[];

  Future<void> setStringList(String key, List<String> value) =>
      _prefs.setStringList(key, value);

  /// Stored as milliseconds since epoch (UTC) to stay timezone independent.
  DateTime? getDateTime(String key) {
    final int? millis = _prefs.getInt(key);
    return millis == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  Future<void> setDateTime(String key, DateTime value) =>
      _prefs.setInt(key, value.toUtc().millisecondsSinceEpoch);

  Future<void> remove(String key) => _prefs.remove(key);
}
