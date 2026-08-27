import 'package:aja/services/storage/key_value_store.dart';
import 'package:aja/services/storage/secure_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Resolved in `bootstrap.dart` and injected through a `ProviderScope`
/// override.
///
/// Doing it this way keeps every synchronous read of a preference synchronous:
/// no `FutureProvider`, no loading spinner for a flag we already have.
final Provider<SharedPreferences> sharedPreferencesProvider =
    Provider<SharedPreferences>(
      (Ref ref) => throw UnimplementedError(
        'sharedPreferencesProvider must be overridden in bootstrap()',
      ),
    );

final Provider<KeyValueStore> keyValueStoreProvider = Provider<KeyValueStore>(
  (Ref ref) => KeyValueStore(ref.watch(sharedPreferencesProvider)),
);

final Provider<SecureStore> secureStoreProvider = Provider<SecureStore>(
  (Ref ref) => const SecureStore(FlutterSecureStorage()),
);
