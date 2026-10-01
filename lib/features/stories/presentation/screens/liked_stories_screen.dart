import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/routing/app_routes.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
import 'package:chismosa/core/widgets/app_loader.dart';
import 'package:chismosa/core/widgets/base_screen.dart';
import 'package:chismosa/core/widgets/empty_state.dart';
import 'package:chismosa/core/widgets/error_view.dart';
import 'package:chismosa/features/stories/domain/story.dart';
import 'package:chismosa/features/stories/presentation/providers/stories_providers.dart';
import 'package:chismosa/features/stories/presentation/widgets/story_card_view.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:chismosa/services/identity/session_guard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Every story the reader swiped right, newest like first.
///
/// The deck deals a card once; this is how a liked one is found again. A tap
/// opens its thread, where the whole story is at the top.
class LikedStoriesScreen extends ConsumerWidget {
  const LikedStoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<List<Story>> liked = ref.watch(likedStoriesProvider);

    return BaseScreen(
      title: l10n.likedTitle,
      showBanner: false,
      body: liked.when(
        loading: () => const AppLoader(),
        error: (Object error, StackTrace _) => ErrorView(
          message: l10n.storiesOfflineBody,
          onRetry: () async {
            await ref.read(sessionGuardProvider).ensureAlive();
            ref.invalidate(likedStoriesProvider);
          },
        ),
        data: (List<Story> rows) => rows.isEmpty
            ? EmptyState(
                icon: Icons.favorite_border,
                title: l10n.storiesLikedEmptyTitle,
                message: l10n.storiesLikedEmptyBody,
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(likedStoriesProvider),
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) =>
                      _Row(story: rows[index]),
                ),
              ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.story});

  final Story story;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TextStyle? meta = context.texts.labelSmall?.copyWith(
      color: context.colors.onSurfaceVariant,
    );

    return ListTile(
      title: Text(
        story.body,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: context.texts.bodyMedium,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Text(
          '${categoryLabel(l10n, story.category)} · '
          '${storyAge(l10n, story.createdAt, DateTime.now().toUtc())} · '
          '${l10n.storiesMessages(story.messagesCount)}',
          style: meta,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.pushNamed(
        AppRoutes.threadName,
        pathParameters: <String, String>{'id': story.id},
      ),
    );
  }
}
