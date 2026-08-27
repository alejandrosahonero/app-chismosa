import 'dart:async';

import 'package:aja/app.dart';
import 'package:aja/core/utils/app_logger.dart';
import 'package:aja/features/facts/presentation/providers/facts_providers.dart';
import 'package:aja/l10n/generated/app_localizations.dart';
import 'package:aja/services/ads/ads_providers.dart';
import 'package:aja/services/billing/premium_controller.dart';
import 'package:aja/services/notifications/daily_question_service.dart';
import 'package:aja/services/notifications/notification_providers.dart';
import 'package:aja/services/review/review_providers.dart';
import 'package:aja/services/storage/storage_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    // Entitlement first: `AdsService` must know whether the user is premium
    // before it requests the first ad.
    await container.read(premiumControllerProvider.future);
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

  try {
    await _initializeDailyQuestion(container);
  } on Object catch (error, stackTrace) {
    AppLogger.error(
      'Daily question initialization failed',
      error: error,
      stackTrace: stackTrace,
    );
  }

  // Last, and never awaited by anything on screen: the download is written to
  // disk and read on the next launch, so that new questions do not appear
  // underneath somebody who is mid-deck.
  unawaited(container.read(remoteCatalogServiceProvider).refresh());
}

/// Wires up the question of the day.
///
/// Runs after the first frame and asks for **no permission**: the switch in
/// Settings is the only thing allowed to do that, because it is the only moment
/// the user has said they want reminders. All this does is listen for taps,
/// honour the one that may have launched the app, and refill the queue.
Future<void> _initializeDailyQuestion(ProviderContainer container) async {
  final DailyQuestionService service = container.read(
    dailyQuestionServiceProvider,
  );

  await service.initialize(
    onOpenFact: (String factId) => openFactFromNotification(container, factId),
  );

  // Locale is read from the platform rather than from a context: this runs
  // outside the widget tree, and the notification text has to match whatever
  // the app is about to render.
  final String language =
      AppLocalizations.supportedLocales
          .map((Locale locale) => locale.languageCode)
          .contains(PlatformDispatcher.instance.locale.languageCode)
      ? PlatformDispatcher.instance.locale.languageCode
      : 'es';

  final AppLocalizations l10n = await AppLocalizations.delegate.load(
    Locale(language),
  );

  // A notification that cold-started the app: the deck is already on screen, so
  // pinning now simply rebuilds it with that card on top.
  final String? launchedWith = await service.launchFactId();
  if (launchedWith != null) {
    openFactFromNotification(container, launchedWith);
  }

  await refreshDailyQuestions(
    container,
    language: language,
    title: l10n.dailyQuestionNotificationTitle,
  );
}
