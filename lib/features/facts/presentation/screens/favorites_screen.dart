import 'package:aja/core/extensions/build_context_x.dart';
import 'package:aja/core/routing/app_routes.dart';
import 'package:aja/core/theme/app_spacing.dart';
import 'package:aja/core/widgets/app_loader.dart';
import 'package:aja/core/widgets/base_screen.dart';
import 'package:aja/core/widgets/empty_state.dart';
import 'package:aja/core/widgets/error_view.dart';
import 'package:aja/features/facts/domain/fact.dart';
import 'package:aja/features/facts/presentation/providers/favorites_controller.dart';
import 'package:aja/features/facts/presentation/widgets/fact_card.dart';
import 'package:aja/features/facts/presentation/widgets/fact_source_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The saved cards, newest first.
///
/// `showBanner: false`: a list of rows with a destructive action (unsave) on
/// each one is exactly the layout where an anchored banner collects accidental
/// clicks — and every reader of this screen is a paying user anyway.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool unlocked = ref.watch(canUseFavoritesProvider);

    return BaseScreen(
      title: context.l10n.favoritesTitle,
      showBanner: false,
      leading: IconButton(
        onPressed: () => context.canPop()
            ? context.pop()
            : context.goNamed(AppRoutes.homeName),
        icon: const Icon(Icons.arrow_back),
      ),
      body: unlocked ? const _FavoritesList() : const _Locked(),
    );
  }
}

/// Shown when the entitlement is missing.
///
/// The saved ids are never deleted, so a refunded — or simply not yet
/// purchased — user finds their list intact if they buy again.
class _Locked extends StatelessWidget {
  const _Locked();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.lock_outline,
      title: context.l10n.premiumFeatureTitle,
      message: context.l10n.premiumFeatureBody,
      action: FilledButton(
        onPressed: () => context.goNamed(AppRoutes.paywallName),
        child: Text(context.l10n.premiumFeatureCta),
      ),
    );
  }
}

class _FavoritesList extends ConsumerWidget {
  const _FavoritesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Fact>> favorites = ref.watch(favoriteFactsProvider);

    return favorites.when(
      loading: () => const AppLoader(),
      error: (Object error, StackTrace stackTrace) =>
          ErrorView(message: context.l10n.deckLoadError),
      data: (List<Fact> facts) {
        if (facts.isEmpty) {
          return EmptyState(
            icon: Icons.bookmark_border,
            title: context.l10n.favoritesEmptyTitle,
            message: context.l10n.favoritesEmptyBody,
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: facts.length,
          itemBuilder: (BuildContext context, int index) =>
              _FavoriteTile(fact: facts[index]),
        );
      },
    );
  }
}

class _FavoriteTile extends ConsumerWidget {
  const _FavoriteTile({required this.fact});

  final Fact fact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String language = Localizations.localeOf(context).languageCode;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Text(
                    fact.question.resolve(language),
                    style: context.texts.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      ref.read(favoritesProvider.notifier).toggle(fact.id),
                  icon: const Icon(Icons.bookmark_remove_outlined),
                  tooltip: context.l10n.favoritesRemove,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(fact.answer.resolve(language), style: context.texts.bodyLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              fact.detail.resolve(language),
              style: context.texts.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FactSourceLink(source: fact.source, url: fact.sourceUrl),
            const SizedBox(height: AppSpacing.xs),
            Text(
              fact.category.label(context),
              style: context.texts.labelSmall?.copyWith(
                color: context.colors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
