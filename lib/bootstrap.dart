import 'dart:async';

import 'package:chismosa/app.dart';
import 'package:chismosa/core/utils/app_logger.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:chismosa/services/ads/ads_providers.dart';
import 'package:chismosa/services/backend/backend_providers.dart';
import 'package:chismosa/services/billing/premium_controller.dart';
import 'package:chismosa/services/locale/locale_providers.dart';
import 'package:chismosa/services/push/push_providers.dart';
import 'package:chismosa/services/push/push_service.dart';
import 'package:chismosa/services/review/review_providers.dart';
import 'package:chismosa/services/storage/storage_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Application entry point logic.
///
/// Startup budget: first frame under 2 s on a mid-range device. Only two things
/// are allowed to run before `runApp`:
///
/// * `WidgetsFlutterBinding.ensureInitialized()`
/// * loading `SharedPreferences` (a few milliseconds, and it lets the theme and
///   the counters render correctly on the very first frame).
///
/// Everything else — AdMob, UMP consent, billing — starts **after** the first
/// frame in [_initializeAfterFirstFrame].
Future<void> bootstrap() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (FlutterErrorDetails details) {
        AppLogger.error(
          'Flutter error',
          error: details.exception,
          stackTrace: details.stack,
        );
        FlutterError.presentError(details);
      };

      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        AppLogger.error('Platform error', error: error, stackTrace: stack);
        return true;
      };

      final SharedPreferences preferences =
          await SharedPreferences.getInstance();

      final ProviderContainer container = ProviderContainer(
        // `Override` is not exported by flutter_riverpod; the literal's type is
        // inferred from the element.
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      );

      unawaited(container.read(reviewServiceProvider).registerAppStart());

      runApp(
        UncontrolledProviderScope(container: container, child: const App()),
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_initializeAfterFirstFrame(container));
      });
    },
    (Object error, StackTrace stackTrace) {
      AppLogger.error(
        'Uncaught zone error',
        error: error,
        stackTrace: stackTrace,
      );
    },
  );
}

/// Deferred initialization. Any failure here degrades a feature; none of it may
/// crash the app or block the UI.
Future<void> _initializeAfterFirstFrame(ProviderContainer container) async {
  try {
    // Backend first: it is what the deck is waiting on, and signing in has to
    // finish before any screen can read or write a thing. A failure here leaves
    // the app in its offline state, not broken.
    final SupabaseClient? client = await initializeBackend();
    if (client != null) {
      container.read(supabaseClientProvider.notifier).attach(client);
      await container.read(identityServiceProvider)?.ensureSignedIn();
      // The profile row exists by now (a trigger creates it on sign-up), so
      // this is where the country and languages the device reports first reach
      // the server. It swallows its own failures: the deck sends its filters
      // with every request, so nothing on screen depends on this landing.
      await container.read(localeSettingsProvider.notifier).syncToProfile();
    }
  } on Object catch (error, stackTrace) {
    AppLogger.error(
      'Backend initialization failed',
      error: error,
      stackTrace: stackTrace,
    );
  }

  try {
    // After sign-in, because the token is registered against the account.
    await _initializePush(container);
  } on Object catch (error, stackTrace) {
    AppLogger.error(
      'Push initialization failed',
      error: error,
      stackTrace: stackTrace,
    );
  }

  try {
    // Entitlement next: `AdsService` must know whether the user is premium
    // before it requests the first ad.
    await container.read(premiumControllerProvider.future);
    // The server lifts the daily posting limit for premium accounts, so the
    // entitlement has to reach the profile row — now, and on every purchase,
    // restore or refund after this.
    await _syncPremiumToProfile(container, container.read(isPremiumProvider));
    container.listen<bool>(
      isPremiumProvider,
      (bool? previous, bool next) =>
          unawaited(_syncPremiumToProfile(container, next)),
    );
  } on Object catch (error, stackTrace) {
    AppLogger.error(
      'Billing initialization failed',
      error: error,
      stackTrace: stackTrace,
    );
  }

  try {
    await container.read(adsServiceProvider).initialize();
    container.read(adsInitializedProvider.notifier).markInitialized();
  } on Object catch (error, stackTrace) {
    AppLogger.error(
      'Ads initialization failed',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

/// Starts FCM, registers this phone's token, and routes taps to threads.
///
/// This asks for **no permission**: that happens
/// after the reader's first message in a thread (`PushService.askPermissionOnce`).
Future<void> _initializePush(ProviderContainer container) async {
  final PushService push = container.read(pushServiceProvider);
  final Locale locale = WidgetsBinding.instance.platformDispatcher.locale;
  final AppLocalizations l10n = lookupAppLocalizations(
    AppLocalizations.supportedLocales.any(
          (Locale l) => l.languageCode == locale.languageCode,
        )
        ? Locale(locale.languageCode)
        : const Locale('es'),
  );
  await push.initialize(
    channelName: l10n.pushChannelName,
    onOpenThread: (String storyId) => openThreadFromPush(container, storyId),
    onForeground: (ThreadPush message) =>
        showForegroundPush(container, message),
  );
  final SupabaseClient? client = container.read(supabaseClientProvider);
  if (client != null) await push.attach(client);
}

/// Mirrors the store entitlement onto `profiles.is_premium`.
///
/// Trusted as the client reports it, which is a known gap: until the purchase
/// token is validated server side (see supabase/README.md, "Pendiente"), a
/// modified app could flip this flag. The worst it buys is unlimited posting,
/// which still goes through every other trigger.
Future<void> _syncPremiumToProfile(
  ProviderContainer container,
  bool isPremium,
) async {
  final SupabaseClient? client = container.read(supabaseClientProvider);
  final String? userId = client?.auth.currentUser?.id;
  if (client == null || userId == null) return;
  try {
    await client
        .from('profiles')
        .update(<String, dynamic>{'is_premium': isPremium})
        .eq('id', userId);
  } on Object catch (error) {
    AppLogger.debug('Could not sync premium: $error', name: 'billing');
  }
}
