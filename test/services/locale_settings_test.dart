/// Country and language inference from the device locale.
///
/// The locale is passed in rather than read off the platform so these
/// assertions do not depend on the machine running them.
library;

import 'dart:ui';

import 'package:chismosa/services/locale/locale_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('inferLocaleSettings', () {
    test('takes the country from the device, uppercased', () {
      final LocaleSettings settings = inferLocaleSettings(
        const Locale('es', 've'),
      );
      expect(settings.countryCode, 'VE');
    });

    test('a missing country is a working state, not an error', () {
      // Plenty of devices report a bare language. The story is published
      // without a country and simply never matches a country filter.
      final LocaleSettings settings = inferLocaleSettings(const Locale('es'));
      expect(settings.countryCode, isNull);
      expect(settings.languages, isNotEmpty);
    });

    test('rejects a country code that is not two letters', () {
      final LocaleSettings settings = inferLocaleSettings(
        const Locale.fromSubtags(languageCode: 'es', countryCode: '419'),
      );
      expect(settings.countryCode, isNull);
    });

    test('seeds the languages with the device language', () {
      final LocaleSettings settings = inferLocaleSettings(
        const Locale('pt', 'BR'),
      );
      expect(settings.languages.first, 'pt');
      expect(settings.writingLanguage, 'pt');
    });

    test('always carries Spanish along', () {
      // Most of what exists early on is written in it, and a deck with nothing
      // in it on the first launch is an app nobody opens twice.
      final LocaleSettings settings = inferLocaleSettings(
        const Locale('fr', 'FR'),
      );
      expect(settings.languages, containsAll(<String>['fr', 'es']));
    });

    test('never repeats Spanish for a Spanish device', () {
      final LocaleSettings settings = inferLocaleSettings(
        const Locale('es', 'MX'),
      );
      expect(settings.languages, <String>['es']);
    });

    test('falls back for a language the app does not offer', () {
      // Selecting it back would be impossible, so it must not be stored.
      final LocaleSettings settings = inferLocaleSettings(
        const Locale('ja', 'JP'),
      );
      expect(settings.languages, <String>['es']);
      expect(settings.countryCode, 'JP');
    });
  });

  group('LocaleSettings', () {
    test('clearing the country is possible', () {
      const LocaleSettings settings = LocaleSettings(
        countryCode: 'VE',
        languages: <String>['es'],
      );
      expect(settings.copyWith(countryCode: null).countryCode, isNull);
    });

    test('an untouched country survives a language change', () {
      const LocaleSettings settings = LocaleSettings(
        countryCode: 'VE',
        languages: <String>['es'],
      );
      final LocaleSettings updated = settings.copyWith(
        languages: <String>['es', 'en'],
      );
      expect(updated.countryCode, 'VE');
      expect(updated.languages, <String>['es', 'en']);
    });
  });
}
