import 'dart:async';

import 'package:chismosa/app.dart';
import 'package:chismosa/core/config/crash_config.dart';
import 'package:chismosa/core/routing/app_router.dart';
import 'package:chismosa/core/routing/app_routes.dart';
import 'package:chismosa/core/utils/app_logger.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:chismosa/services/ads/ads_providers.dart';
import 'package:chismosa/services/backend/backend_providers.dart';
import 'package:chismosa/services/billing/premium_controller.dart';
import 'package:chismosa/services/identity/install_claim.dart';
import 'package:chismosa/services/locale/locale_providers.dart';
import 'package:chismosa/services/push/push_providers.dart';
import 'package:chismosa/services/push/push_service.dart';
import 'package:chismosa/services/review/review_providers.dart';
import 'package:chismosa/services/storage/storage_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
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

      // The OFL requires the licence to travel with the fonts. Lazy: the files
      // are only read if somebody opens the licence page.
      LicenseRegistry.addLicense(() async* {
        for (final (String family, String file) in <(String, String)>[
          ('Bricolage Grotesque', 'OFL-BricolageGrotesque.txt'),
          ('Onest', 'OFL-Onest.txt'),
        ]) {
          yield LicenseEntryWithLineBreaks(<String>[
            family,
          ], await rootBundle.loadString('assets/fonts/$file'));
        }
      });

      // Before anything that can crash, so startup crashes are reported. The
      // handlers below replace Sentry's and forward through AppLogger.
      if (CrashConfig.enabled) {
        await SentryFlutter.init((SentryFlutterOptions options) {
          options
            ..dsn = CrashConfig.sentryDsn
            ..tracesSampleRate = 0
            ..sendDefaultPii = false;
        });
      }

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
        // No automatic retries. Riverpod 3 retries failed providers by
        // default and reports them as loading meanwhile, so an unreachable
        // server looked like a spinner that never ends. Every screen has
        // its own retry button; failures must reach it.
        retry: (int retryCount, Object error) => null,
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
      await checkInstallClaim(container);
      // A phone that was left in the background while the account moved to
      // another one finds out the moment it comes back.
      AppLifecycleListener(
        onResume: () => unawaited(checkInstallClaim(container)),
      );
      // The profile row exists by now (a trigger creates it on sign-up), so
      // this is where the country and languages the device reports first reach
      // the server. It swallows its own failures: the deck sends its filters
      // with every request, so nothing on screen depends on this landing.
      await container.read(localeSettingsProvider.notifier).syncToProfile();
      // One row touched per app open: this is what active users are counted
      // from (tool/stats.sql). Best effort, like the line above.
      unawaited(
        client.rpc<void>('touch_session').then((_) {}, onError: (Object _) {}),
      );
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
    // The cached purchase is checked with Google again on every start: a
    // refund never reaches the purchase stream, so this is the only way it
    // takes premium away. Not awaited — the ads below only need the cache.
    unawaited(container.read(premiumControllerProvider.notifier).reverify());
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
    onOpenMyStories: () =>
        container.read(routerProvider).pushNamed(AppRoutes.myStoriesName),
    onForeground: (ThreadPush message) =>
        showForegroundPush(container, message),
  );
  final SupabaseClient? client = container.read(supabaseClientProvider);
  if (client != null) await push.attach(client);
}

/// Asks the server whether this phone may use the signed-in account and, if
/// not, sends the app to the "on another phone" screen.
Future<void> checkInstallClaim(ProviderContainer container) async {
  final ClaimResult result = await container.read(installClaimProvider).claim();
  final bool moved = result == ClaimResult.moved;
  if (container.read(accountMovedProvider) == moved) return;
  container.read(accountMovedProvider.notifier).set(moved: moved);
  container
      .read(routerProvider)
      .goNamed(moved ? AppRoutes.movedName : AppRoutes.homeName);
}
