import 'package:chismosa/core/utils/app_logger.dart';
import 'package:chismosa/services/backend/backend_providers.dart';
import 'package:chismosa/services/locale/locale_settings.dart';
import 'package:chismosa/services/storage/key_value_store.dart';
import 'package:chismosa/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Country and languages, resolved synchronously at first read.
///
/// Synchronous because it is on the path to the first deck request: preferences
/// are already in memory when `bootstrap()` finishes, and the device locale is
/// a property, not a query. A `FutureProvider` here would mean a spinner in
/// front of the deck for something the app already knows.
final NotifierProvider<LocaleController, LocaleSettings>
localeSettingsProvider = NotifierProvider<LocaleController, LocaleSettings>(
  LocaleController.new,
);

class LocaleController extends Notifier<LocaleSettings> {
  static const String _languagesKey = 'locale_languages';

  @override
  LocaleSettings build() {
    final KeyValueStore store = ref.read(keyValueStoreProvider);
    final LocaleSettings inferred = inferLocaleSettings();
    final List<String> saved = store.getStringList(_languagesKey);

    // The country is re-read from the device every launch rather than restored:
    // people move, and a stored country would keep filing somebody's stories
    // under the country they installed the app in. The languages are the
    // opposite — they are a choice, so the stored value wins.
    return inferred.copyWith(
      languages: saved.isEmpty ? inferred.languages : saved,
    );
  }

  /// Replaces the language selection.
  ///
  /// An empty selection is refused rather than stored: a reader with no
  /// languages gets an empty deck, and there would be no card left on screen to
  /// explain why.
  Future<void> setLanguages(List<String> languages) async {
    final List<String> valid = languages
        .where(kSelectableLanguages.contains)
        .toSet()
        .toList(growable: false);
    if (valid.isEmpty) return;

    state = state.copyWith(languages: valid);
    await ref.read(keyValueStoreProvider).setStringList(_languagesKey, valid);
    await syncToProfile();
  }

  /// Pushes country and languages onto the profile row.
  ///
  /// The server needs them for nothing the reader sees — the deck sends its own
  /// filters with every request — but a group's feed and, later, the push
  /// digest are built server side, and those cannot ask the phone.
  ///
  /// Failure is swallowed on purpose: this is bookkeeping, and a reader with no
  /// connection must still get a deck out of the cache.
  Future<void> syncToProfile() async {
    final SupabaseClient? client = ref.read(supabaseClientProvider);
    final String? userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) return;

    try {
      await client
          .from('profiles')
          .update(<String, dynamic>{
            'country_code': state.countryCode,
            'languages': state.languages,
          })
          .eq('id', userId);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Could not sync locale to profile',
        error: error,
        stackTrace: stackTrace,
        name: 'locale',
      );
    }
  }
}
