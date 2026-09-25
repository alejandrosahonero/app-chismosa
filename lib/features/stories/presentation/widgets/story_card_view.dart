import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/theme/app_colors.dart';
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
  const StoryCardView({required this.story, super.key, this.onMore});

  final Story story;

  /// Opens report / block. Only the top card gets one: the cards behind are
  /// covered and cannot be tapped anyway.
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;
    final AppSemanticColors brand = context.semanticColors;
    // Short stories are set bigger. A two-line confession in the same size as
    // a 600-character saga looks lost in the middle of the card; set large it
    // reads like something said out loud.
    final TextStyle? bodyStyle =
        (story.body.length <= 140
                ? context.texts.headlineMedium
                : context.texts.headlineSmall)
            ?.copyWith(
              height: 1.3,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
              color: brand.onPaper,
            );

    return RepaintBoundary(
      child: DeckCardShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Header(story: story, onMore: onMore),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              // Centred while it fits, scrolling once it does not: a short
              // story sits in the middle of the card like something said out
              // loud, and a 600-character one still never shrinks its type.
              child: Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // The opening quote is the brand's signature on every
                      // card: this is somebody's voice, reported — which is
                      // what gossip is.
                      ExcludeSemantics(
                        child: SizedBox(
                          height: 44,
                          child: Text(
                            '“',
                            style: TextStyle(
                              fontSize: 72,
                              height: 0.9,
                              fontWeight: FontWeight.w900,
                              color: brand.quote,
                            ),
                          ),
                        ),
                      ),
                      Text(story.body, style: bodyStyle),
                    ],
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
  const _Header({required this.story, this.onMore});

  final Story story;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = context.colors;

    return Row(
      children: <Widget>[
        _Pill(
          label: categoryLabel(context.l10n, story.category),
          background: colors.secondaryContainer,
          foreground: colors.onSecondaryContainer,
        ),
        if (story.isHouse) ...<Widget>[
          const SizedBox(width: AppSpacing.xs),
          _Pill(
            label: context.l10n.storiesHouse,
            background: colors.primaryContainer,
            foreground: colors.onPrimaryContainer,
          ),
        ],
        if (story.chapter > 1) ...<Widget>[
          const SizedBox(width: AppSpacing.xs),
          _Pill(
            label: context.l10n.storiesChapter(story.chapter),
            background: colors.tertiaryContainer,
            foreground: colors.onTertiaryContainer,
          ),
        ],
        const SizedBox(width: AppSpacing.sm),
        Text(
          storyAge(context.l10n, story.createdAt, DateTime.now().toUtc()),
          style: context.texts.labelMedium?.copyWith(
            color: colors.onSurfaceVariant,
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
        if (onMore != null)
          IconButton(
            onPressed: onMore,
            tooltip: context.l10n.moderationMore,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.more_vert),
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

/// How long ago, in the fewest characters that still say it: "ahora", "12 min",
/// "3 h", "5 d". Freshness is half of what makes gossip gossip.
String storyAge(AppLocalizations l10n, DateTime createdAt, DateTime now) {
  final Duration age = now.difference(createdAt);
  if (age.inMinutes < 1) return l10n.storiesAgeNow;
  if (age.inHours < 1) return l10n.storiesAgeMinutes(age.inMinutes);
  if (age.inDays < 1) return l10n.storiesAgeHours(age.inHours);
  return l10n.storiesAgeDays(age.inDays);
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: context.texts.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
