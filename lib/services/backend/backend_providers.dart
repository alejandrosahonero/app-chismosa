import 'package:chismosa/core/config/backend_config.dart';
import 'package:chismosa/core/utils/app_logger.dart';
import 'package:chismosa/services/identity/anonymous_identity_service.dart';
import 'package:chismosa/services/identity/identity_backend.dart';
import 'package:chismosa/services/identity/secret_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Whether the app has a backend at all this build.
///
/// Every screen reads this instead of checking the config, so an unconfigured
/// build degrades in one place: the deck shows its offline state, publishing is
/// disabled, and nothing throws.
final Provider<bool> backendConfiguredProvider = Provider<bool>(
  (Ref ref) => BackendConfig.isConfigured,
);

/// The client, once `bootstrap()` has started it.
///
/// A notifier and not a `ProviderScope` override, unlike
/// `sharedPreferencesProvider`: this one is only ready **after the first
/// frame**, because connecting is a network round trip and the deck can render
/// its loading state without it. Null until then, and null forever in a build
/// with no project configured.
final NotifierProvider<BackendClientNotifier, SupabaseClient?>
supabaseClientProvider =
    NotifierProvider<BackendClientNotifier, SupabaseClient?>(
      BackendClientNotifier.new,
    );

class BackendClientNotifier extends Notifier<SupabaseClient?> {
  @override
  SupabaseClient? build() => null;

  void attach(SupabaseClient client) => state = client;
}

/// KeepAlive on purpose: it owns the auth session and the recovery secret, and
/// re-creating it mid-session would sign the user in twice.
final Provider<AnonymousIdentityService?> identityServiceProvider =
    Provider<AnonymousIdentityService?>((Ref ref) {
      final SupabaseClient? client = ref.watch(supabaseClientProvider);
      if (client == null) return null;
      return AnonymousIdentityService(
        backend: SupabaseIdentityBackend(client.auth),
        store: FileSecretStore(),
      );
    });

/// Id of the signed-in anonymous account, or null before sign-in finishes.
final Provider<String?> currentUserIdProvider = Provider<String?>(
  (Ref ref) => ref.watch(identityServiceProvider)?.identity?.userId,
);

/// Starts Supabase. Returns null when the project is not configured yet.
///
/// Called from `bootstrap()` **after the first frame**: signing in is a network
/// round trip, and nothing on the first screen needs it.
Future<SupabaseClient?> initializeBackend() async {
  if (!BackendConfig.isConfigured) {
    AppLogger.debug('Backend not configured; running offline', name: 'backend');
    return null;
  }
  await Supabase.initialize(
    url: BackendConfig.url,
    publishableKey: BackendConfig.publishableKey,
    // The deck and the threads decide when to talk to the network; the SDK
    // should not also be reconnecting on its own schedule while the app is in
    // the background, where the free plan's 200 realtime slots are wasted.
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 10),
  );
  return Supabase.instance.client;
}
