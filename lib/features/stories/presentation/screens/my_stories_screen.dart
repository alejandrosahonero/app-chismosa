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
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The author's side of the app: what they posted and how it is doing.
///
/// Writers are this app's supply, and nothing brings a writer back like
/// seeing that strangers read, liked and argued about what they wrote. This is
/// also where a story gets its next part.
class MyStoriesScreen extends ConsumerWidget {
  const MyStoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final AsyncValue<List<OwnStory>> stories = ref.watch(myStoriesProvider);

    return BaseScreen(
      title: l10n.myStoriesTitle,
      showBanner: false,
      body: stories.when(
        loading: () => const AppLoader(),
        error: (Object error, StackTrace _) => ErrorView(
          message: l10n.storiesOfflineBody,
          onRetry: () => ref.invalidate(myStoriesProvider),
        ),
        data: (List<OwnStory> rows) => rows.isEmpty
            ? EmptyState(
                icon: Icons.edit_note,
                title: l10n.myStoriesEmptyTitle,
                message: l10n.myStoriesEmptyBody,
                action: FilledButton.icon(
                  onPressed: () => context.goNamed(AppRoutes.composeName),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(l10n.storiesEmptyWrite),
                ),
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(myStoriesProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: rows.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (BuildContext context, int index) =>
                      _OwnStoryTile(story: rows[index]),
                ),
              ),
      ),
    );
  }
}

class _OwnStoryTile extends StatelessWidget {
  const _OwnStoryTile({required this.story});

  final OwnStory story;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final TextStyle? meta = context.texts.labelMedium?.copyWith(
      color: context.colors.onSurfaceVariant,
    );

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: story.hidden
            ? null
            : () => context.pushNamed(
                AppRoutes.threadName,
                pathParameters: <String, String>{'id': story.id},
              ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  if (story.chapter > 1) ...<Widget>[
                    Text(
                      l10n.storiesChapter(story.chapter),
                      style: meta?.copyWith(
                        color: context.colors.tertiary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Text(
                    storyAge(l10n, story.createdAt, DateTime.now().toUtc()),
                    style: meta,
                  ),
                  if (story.groupId != null) ...<Widget>[
                    const SizedBox(width: AppSpacing.sm),
                    Icon(
                      Icons.groups_outlined,
                      size: 16,
                      color: context.colors.onSurfaceVariant,
                    ),
                  ],
                  const Spacer(),
                  if (story.hidden)
                    Text(
                      l10n.myStoriesHidden,
                      style: meta?.copyWith(color: context.colors.error),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                story.body,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: <Widget>[
                  Icon(Icons.favorite, size: 16, color: context.colors.primary),
                  const SizedBox(width: AppSpacing.xs),
                  Text('${story.likesCount}', style: meta),
                  const SizedBox(width: AppSpacing.md),
                  Icon(Icons.forum, size: 16, color: context.colors.secondary),
                  const SizedBox(width: AppSpacing.xs),
                  Text('${story.messagesCount}', style: meta),
                  const Spacer(),
                  if (story.canContinue)
                    TextButton.icon(
                      onPressed: () => context.pushNamed(
                        AppRoutes.composeName,
                        extra: story,
                      ),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.myStoriesContinue(story.chapter + 1)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
