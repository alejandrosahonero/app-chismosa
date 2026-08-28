import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
import 'package:chismosa/core/widgets/deck/deck_card_shell.dart';
import 'package:chismosa/features/stories/domain/story.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// Localized name of a category.
String categoryLabel(AppLocalizations l10n, StoryCategory category) =>
    switch (category) {
      StoryCategory.anything => l10n.storiesCategoryAnything,
      StoryCategory.love => l10n.storiesCategoryLove,
      StoryCategory.family => l10n.storiesCategoryFamily,
      StoryCategory.work => l10n.storiesCategoryWork,
      StoryCategory.friendship => l10n.storiesCategoryFriendship,
      StoryCategory.school => l10n.storiesCategorySchool,
      StoryCategory.neighbours => l10n.storiesCategoryNeighbours,
      StoryCategory.money => l10n.storiesCategoryMoney,
    };

/// One story, front and centre.
///
/// There is no back side and nothing to flip: the story **is** the card. The
/// deck it grew out of hid an answer behind a gesture because a question is
/// worthless without one; here the whole point is that a stranger's story can
/// be read in three seconds and swiped.
///
/// Wrapped in a [RepaintBoundary] because the cards underneath must not repaint
/// while this one is being dragged.
class StoryCardView extends StatelessWidget {
  const StoryCardView({required this.story, super.key});

  final Story story;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final ColorScheme colors = context.colors;

    return RepaintBoundary(
      child: DeckCardShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Header(story: story),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: SingleChildScrollView(
                // A long story scrolls inside the card rather than shrinking
                // its own type past readable: 600 characters at a size chosen
                // to fit the worst case would be unpleasant for all the rest.
                physics: const ClampingScrollPhysics(),
                child: Text(
                  story.body,
                  style: context.texts.headlineSmall?.copyWith(
                    height: 1.35,
                    color: colors.onSurface,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _Footer(story: story, l10n: l10n),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.story});

  final Story story;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = context.colors;

    return Row(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            categoryLabel(context.l10n, story.category),
            style: context.texts.labelSmall?.copyWith(
              color: colors.onPrimaryContainer,
            ),
          ),
        ),
        const Spacer(),
        if (story.countryCode != null)
          Text(
            // The flag is built from the country code itself: two regional
            // indicator letters. No asset, no lookup table, and nothing to
            // update when a country changes its name.
            _flagOf(story.countryCode!),
            style: const TextStyle(fontSize: 20),
          ),
      ],
    );
  }

  static String _flagOf(String code) {
    const int base = 0x1F1E6;
    const int a = 0x41;
    return String.fromCharCodes(<int>[
      base + code.codeUnitAt(0) - a,
      base + code.codeUnitAt(1) - a,
    ]);
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.story, required this.l10n});

  final Story story;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = context.colors;
    final TextStyle? style = context.texts.labelMedium?.copyWith(
      color: colors.onSurfaceVariant,
    );

    return Row(
      children: <Widget>[
        Icon(
          story.liked ? Icons.favorite : Icons.favorite_border,
          size: 16,
          color: story.liked ? colors.primary : colors.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(story.likesCount.toString(), style: style),
        const SizedBox(width: AppSpacing.md),
        Icon(
          Icons.forum_outlined,
          size: 16,
          color: story.joined ? colors.primary : colors.onSurfaceVariant,
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(story.messagesCount.toString(), style: style),
        const Spacer(),
        if (story.isClosed)
          Text(l10n.storiesThreadClosed, style: style)
        else if (story.joined)
          Text(l10n.storiesJoinedThread, style: style),
      ],
    );
  }
}
