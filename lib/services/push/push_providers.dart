import 'package:chismosa/core/routing/app_router.dart';
import 'package:chismosa/core/routing/app_routes.dart';
import 'package:chismosa/features/threads/presentation/providers/thread_controller.dart';
import 'package:chismosa/features/threads/presentation/providers/threads_providers.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:chismosa/services/push/push_service.dart';
import 'package:chismosa/services/storage/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Kept alive: it owns the FCM subscriptions for the life of the process.
final Provider<PushService> pushServiceProvider = Provider<PushService>((
  Ref ref,
) {
  final PushService service = PushService(ref.watch(keyValueStoreProvider));
  ref.onDispose(service.dispose);
  return service;
});

/// Opens the thread behind a tapped notification, from wherever the app is.
void openThreadFromPush(ProviderContainer container, String storyId) {
  container.invalidate(myThreadsProvider);
  container
      .read(routerProvider)
      .pushNamed(
        AppRoutes.threadName,
        pathParameters: <String, String>{'id': storyId},
      );
}

/// A push that arrived with the app open.
///
/// Android shows nothing on its own in the foreground, and that is mostly
/// right: if the reader is looking at that very thread, the message is already
/// on screen through Realtime and a banner would only repeat it. Anywhere else
/// a snackbar says it once, with a way in.
void showForegroundPush(ProviderContainer container, ThreadPush push) {
  container.invalidate(myThreadsProvider);

  final String? open = container.read(threadControllerProvider).value?.story.id;
  if (open == push.storyId) return;

  final BuildContext? context = rootNavigatorKey.currentContext;
  if (context == null) return;
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  final AppLocalizations l10n = AppLocalizations.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          push.body ?? l10n.pushNewMessage,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        action: SnackBarAction(
          label: l10n.pushOpen,
          onPressed: () => openThreadFromPush(container, push.storyId),
        ),
      ),
    );
}
