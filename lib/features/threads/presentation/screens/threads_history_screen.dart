import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/routing/app_routes.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
import 'package:chismosa/core/widgets/app_loader.dart';
import 'package:chismosa/core/widgets/base_screen.dart';
import 'package:chismosa/core/widgets/empty_state.dart';
import 'package:chismosa/core/widgets/error_view.dart';
import 'package:chismosa/features/threads/domain/thread_message.dart';
import 'package:chismosa/features/threads/presentation/providers/threads_providers.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:chismosa/services/identity/session_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Every conversation this reader has walked into.
///
/// This is the only place a story can be found again. The deck deals each card
/// once and never brings it back, which is deliberate — but a conversation the
/// reader answered in is not a card, and losing it would make answering feel
/// pointless.
class ThreadsHistoryScreen extends ConsumerWidget {
  const ThreadsHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<List<ThreadSummary>> threads = ref.watch(
      myThreadsProvider,
    );

    return BaseScreen(
      title: l10n.threadsTitle,
      showBanner: false,
      actions: <Widget>[
        IconButton(
          onPressed: () => context.pushNamed(AppRoutes.myStoriesName),
          icon: const Icon(Icons.edit_note),
          tooltip: l10n.myStoriesTitle,
        ),
      ],
      body: threads.when(
        loading: () => const AppLoader(),
        error: (Object error, StackTrace _) => ErrorView(
          message: l10n.storiesOfflineBody,
          onRetry: () async {
            await ref.read(sessionGuardProvider).ensureAlive();
            ref.invalidate(myThreadsProvider);
          },
        ),
        data: (List<ThreadSummary> rows) => rows.isEmpty
            ? EmptyState(
                icon: Icons.forum_outlined,
                title: l10n.threadsEmptyTitle,
                message: l10n.threadsEmptyBody,
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(myThreadsProvider),
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) =>
                      _Row(summary: rows[index]),
                ),
              ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.summary});

  final ThreadSummary summary;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return ListTile(
      title: Text(
        summary.body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: context.texts.bodyMedium,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Row(
          children: <Widget>[
            if (summary.isMine) ...<Widget>[
              Text(
                l10n.threadsYourStory,
                style: context.texts.labelSmall?.copyWith(
                  color: context.colors.tertiary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            // The alias first: it is how the reader recognises which of their
            // selves was in this conversation.
            Text(
              summary.alias,
              style: context.texts.labelSmall?.copyWith(
                color: context.colors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              l10n.storiesMessages(summary.messagesCount),
              style: context.texts.labelSmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            if (summary.muted) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.notifications_off_outlined,
                size: 14,
                color: context.colors.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
      trailing: summary.unreadCount == 0
          ? const Icon(Icons.chevron_right)
          : Badge(label: Text(summary.unreadCount.toString())),
      onTap: () => context.pushNamed(
        AppRoutes.threadName,
        pathParameters: <String, String>{'id': summary.storyId},
      ),
    );
  }
}
