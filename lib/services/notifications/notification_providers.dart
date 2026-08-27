import 'package:aja/core/routing/app_router.dart';
import 'package:aja/core/routing/app_routes.dart';
import 'package:aja/features/facts/presentation/providers/facts_providers.dart';
import 'package:aja/services/notifications/daily_question_service.dart';
import 'package:aja/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Kept alive: it owns the plugin instance and the tap callback, which have to
/// outlive any single screen.
final Provider<DailyQuestionService> dailyQuestionServiceProvider =
    Provider<DailyQuestionService>(
      (Ref ref) => DailyQuestionService(ref.watch(keyValueStoreProvider)),
    );

/// Takes the app to the question behind a tapped notification.
///
/// Three things have to happen together, which is why they live in one function
/// instead of scattered across the call sites:
///
/// 1. **The category filter is cleared.** The question of the day is drawn from
///    the whole catalogue, so a user left on "Historia" would tap a science
///    notification and be shown nothing at all.
/// 2. **The fact is pinned**, which lifts it to the top of the deck without
///    skipping anything — see `DeckController._hoist`.
/// 3. **The app navigates home**, because the tap can land while the user is
///    parked on Settings, favourites or the paywall.
void openFactFromNotification(ProviderContainer container, String factId) {
  container.read(categoryFilterProvider.notifier).select(null);
  container.read(pinnedFactProvider.notifier).pin(factId);
  container.read(routerProvider).goNamed(AppRoutes.homeName);
}

/// Tops the notification queue up, using the catalogue the app has loaded.
///
/// Called on every app open: the queue is finite by design, so refilling it is
/// what keeps the reminders arriving.
Future<void> refreshDailyQuestions(
  ProviderContainer container, {
  required String language,
  required String title,
}) async {
  final DailyQuestionService service = container.read(
    dailyQuestionServiceProvider,
  );
  if (!service.isEnabled) return;

  await service.reschedule(
    facts: await container.read(factsProvider.future),
    language: language,
    title: title,
  );
}
