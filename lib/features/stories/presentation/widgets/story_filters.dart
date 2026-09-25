import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/routing/app_routes.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
import 'package:chismosa/features/groups/domain/story_group.dart';
import 'package:chismosa/features/groups/presentation/providers/groups_providers.dart';
import 'package:chismosa/features/stories/domain/feed_query.dart';
import 'package:chismosa/features/stories/domain/story.dart';
import 'package:chismosa/features/stories/presentation/providers/stories_providers.dart';
import 'package:chismosa/features/stories/presentation/widgets/story_card_view.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:chismosa/services/locale/locale_providers.dart';
import 'package:chismosa/services/locale/locale_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// One scrollable row holding every filter the deck has.
///
/// A row and not a menu: these chips cost vertical space the card would
/// otherwise have, but they show what the deck can be filtered by without
/// opening anything, and changing one is a single tap instead of three. It is
/// also the one control that stays useful on the "nothing left" screen, which
/// is exactly where changing a filter is the most helpful thing a reader can
/// do.
///
/// Tapping the selected chip again does **not** clear it: in a row of filters a
/// tap means "show me this one".
class StoryFilters extends ConsumerWidget {
  const StoryFilters({super.key});

  /// Comfortably over the 48dp touch target once the chip's own tap padding is
  /// counted, and small enough that the card keeps the screen.
  static const double height = 40;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FeedQuery query = ref.watch(feedQueryProvider);
    final AppLocalizations l10n = context.l10n;
    final String? myCountry = ref.watch(
      localeSettingsProvider.select(
        (LocaleSettings value) => value.countryCode,
      ),
    );

    return SizedBox(
      height: height,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: <Widget>[
          // Which deck this is, before how it is filtered: a group is a
          // different deck, not a narrower one. Tapping opens the groups
          // screen, which is where switching back to the world lives too.
          _Chip(
            label: _deckName(ref, query.groupId) ?? l10n.groupsWorldwide,
            icon: query.groupId == null ? Icons.public : Icons.groups_outlined,
            selected: query.groupId != null,
            onTap: () => context.pushNamed(AppRoutes.groupsName),
          ),
          const SizedBox(width: AppSpacing.md),
          // Sort first: it changes what the deck *is*, while a category only
          // narrows it.
          _Chip(
            label: query.sort == StorySort.hot
                ? l10n.storiesSortHot
                : l10n.storiesSortNew,
            icon: query.sort == StorySort.hot
                ? Icons.local_fire_department_outlined
                : Icons.schedule,
            selected: true,
            onTap: () => ref
                .read(feedQueryProvider.notifier)
                .selectSort(
                  query.sort == StorySort.hot
                      ? StorySort.newest
                      : StorySort.hot,
                ),
          ),
          if (myCountry != null) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            _Chip(
              label: query.countryCode == null
                  ? l10n.storiesCountryAll
                  : l10n.storiesCountryMine,
              icon: Icons.public,
              selected: query.countryCode != null,
              onTap: () => ref
                  .read(feedQueryProvider.notifier)
                  .selectCountry(query.countryCode == null ? myCountry : null),
            ),
          ],
          const SizedBox(width: AppSpacing.md),
          _Chip(
            label: l10n.storiesCategoryAll,
            selected: query.category == null,
            onTap: () =>
                ref.read(feedQueryProvider.notifier).selectCategory(null),
          ),
          for (final StoryCategory category
              in StoryCategory.filters) ...<Widget>[
            const SizedBox(width: AppSpacing.sm),
            _Chip(
              label: categoryLabel(l10n, category),
              selected: query.category == category,
              onTap: () =>
                  ref.read(feedQueryProvider.notifier).selectCategory(category),
            ),
          ],
        ],
      ),
    );
  }
}

/// The selected group's name, or null for the worldwide deck. Also null for a
/// group the list has not loaded yet, which shows as the generic label for a
/// moment rather than as an empty chip.
String? _deckName(WidgetRef ref, String? groupId) {
  if (groupId == null) return null;
  final List<StoryGroup> groups =
      ref.watch(myGroupsProvider).value ?? const <StoryGroup>[];
  for (final StoryGroup group in groups) {
    if (group.id == groupId) return group.name;
  }
  return null;
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      avatar: icon == null
          ? null
          : Icon(
              icon,
              size: 16,
              color: selected
                  ? context.colors.onSecondaryContainer
                  : context.colors.onSurfaceVariant,
            ),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
