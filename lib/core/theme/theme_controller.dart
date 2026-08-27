import 'package:aja/services/storage/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Persisted light/dark/system preference.
///
/// Synchronous by design: the value comes from `SharedPreferences`, which is
/// already loaded in `bootstrap`, so the first frame paints with the right
/// theme and never flashes the wrong brightness.
final NotifierProvider<ThemeModeController, ThemeMode> themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  static const String _storageKey = 'theme_mode';

  @override
  ThemeMode build() {
    final String? stored = ref
        .watch(keyValueStoreProvider)
        .getString(_storageKey);

    return switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await ref.read(keyValueStoreProvider).setString(_storageKey, mode.name);
  }
}
