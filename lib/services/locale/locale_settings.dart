import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Where the reader is and which languages they read.
///
/// Both come from the **device locale**, never from GPS. Asking for a location
/// permission to put a flag on a card would be a terrible trade: the permission
/// dialog costs installs, and a story is filed by country, which the phone
/// already knows.
@immutable
class LocaleSettings {
  const LocaleSettings({required this.countryCode, required this.languages});

  /// Two uppercase letters, or null when the device did not report a country.
  /// Null is a working state: the story is published without one and simply
  /// never matches a country filter.
  final String? countryCode;

  /// Languages whose stories the deck deals, most preferred first. Never
  /// empty — an empty list would mean a reader who is shown nothing.
  final List<String> languages;

  /// Language a story written on this device is filed under.
  String get writingLanguage => languages.first;

  LocaleSettings copyWith({
    Object? countryCode = _unset,
    List<String>? languages,
  }) => LocaleSettings(
    countryCode: countryCode == _unset
        ? this.countryCode
        : countryCode as String?,
    languages: languages ?? this.languages,
  );

  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      other is LocaleSettings &&
      other.countryCode == countryCode &&
      listEquals(other.languages, languages);

  @override
  int get hashCode => Object.hash(countryCode, Object.hashAll(languages));
}

/// Languages the preferences screen offers.
///
/// A short list on purpose. Every entry here is a promise that the deck has
/// something to deal in it, and a picker with two hundred rows of which five
/// have content is a worse experience than one with six.
const List<String> kSelectableLanguages = <String>[
  'es',
  'en',
  'pt',
  'fr',
  'it',
  'de',
];

/// Reads the country and the starting language off the platform.
///
/// Split out from the controller so it can be handed a fake locale in tests —
/// otherwise every assertion here would depend on the machine running them.
LocaleSettings inferLocaleSettings([Locale? locale]) {
  final Locale device = locale ?? PlatformDispatcher.instance.locale;

  final String? country = _normalizeCountry(device.countryCode);
  final String language = _normalizeLanguage(device.languageCode);

  return LocaleSettings(
    countryCode: country,
    // Seeded from the device and editable afterwards. Spanish tags along for
    // anyone whose phone is not in it, because that is the language most of
    // the early catalogue is written in, and a deck with nothing in it on the
    // first launch is an app the user never opens twice.
    languages: <String>{language, 'es'}.toList(growable: false),
  );
}

String? _normalizeCountry(String? raw) {
  if (raw == null) return null;
  final String value = raw.toUpperCase();
  return RegExp(r'^[A-Z]{2}$').hasMatch(value) ? value : null;
}

String _normalizeLanguage(String raw) {
  final String value = raw.toLowerCase();
  // Two letters is what the column checks; a tag like `zh-Hant` or a stray
  // empty string must not become a language nobody can select back.
  if (value.length != 2 || !kSelectableLanguages.contains(value)) return 'es';
  return value;
}
