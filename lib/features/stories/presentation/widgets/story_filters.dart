import 'package:chismosa/core/extensions/build_context_x.dart';
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

/// The filters button in the deck's app bar.
///
/// An icon, not a row of chips: the row cost the card vertical space and read
/// as a wall of buttons. A dot on the icon says some filter is on.
class StoryFiltersButton extends ConsumerWidget {
  const StoryFiltersButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FeedQuery query = ref.watch(feedQueryProvider);
    final String? myCountry = ref.watch(
      localeSettingsProvider.select(
        (LocaleSettings value) => value.countryCode,
      ),
    );
    final int active = <bool>[
      query.sort != StorySort.hot,
      query.category != null,
      // The deck starts on the reader's country; widening it is the change.
      myCountry != null && query.countryCode == null,
    ].where((bool on) => on).length;

    return IconButton(
      tooltip: context.l10n.storiesFilters,
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (BuildContext context) => const _FilterSheet(),
      ),
      icon: Badge(
        isLabelVisible: active > 0,
        label: Text('$active'),
        child: const Icon(Icons.tune),
      ),
    );
  }
}

/// Sort, country and category, one tap each. Changes apply as they are made:
/// the deck behind the sheet is already reshuffling when it closes.
class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FeedQuery query = ref.watch(feedQueryProvider);
    final FeedQueryController filters = ref.read(feedQueryProvider.notifier);
    final AppLocalizations l10n = context.l10n;
    final String? myCountry = ref.watch(
      localeSettingsProvider.select(
        (LocaleSettings value) => value.countryCode,
      ),
    );

    Widget title(String text) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
      child: Text(text, style: context.texts.titleSmall),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            title(l10n.storiesFilterSort),
            Wrap(
              spacing: AppSpacing.sm,
              children: <Widget>[
                _Chip(
                  label: l10n.storiesSortHot,
                  icon: Icons.local_fire_department_outlined,
                  selected: query.sort == StorySort.hot,
                  onTap: () => filters.selectSort(StorySort.hot),
                ),
                _Chip(
                  label: l10n.storiesSortNew,
                  icon: Icons.schedule,
                  selected: query.sort == StorySort.newest,
                  onTap: () => filters.selectSort(StorySort.newest),
                ),
              ],
            ),
            if (myCountry != null) ...<Widget>[
              title(l10n.storiesFilterWhere),
              Wrap(
                spacing: AppSpacing.sm,
                children: <Widget>[
                  _Chip(
                    label: l10n.storiesCountryMine,
                    selected: query.countryCode != null,
                    onTap: () => filters.selectCountry(myCountry),
                  ),
                  _Chip(
                    label: l10n.storiesCountryAll,
                    icon: Icons.public,
                    selected: query.countryCode == null,
                    onTap: () => filters.selectCountry(null),
                  ),
                ],
              ),
            ],
            title(l10n.storiesFilterCategory),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: <Widget>[
                _Chip(
                  label: l10n.storiesCategoryAll,
                  selected: query.category == null,
                  onTap: () => filters.selectCategory(null),
                ),
                for (final StoryCategory category in StoryCategory.filters)
                  _Chip(
                    label: categoryLabel(l10n, category),
                    selected: query.category == category,
                    onTap: () => filters.selectCategory(category),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The selected group's name, or null for the worldwide deck. Also null for a
/// group the list has not loaded yet, which shows as the generic label for a
/// moment rather than as an empty chip.
String? deckName(WidgetRef ref, String? groupId) {
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
                  ? context.colors.onPrimary
                  : context.colors.onSurfaceVariant,
            ),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
