import 'package:aja/features/facts/domain/fact.dart';
import 'package:aja/features/facts/presentation/providers/facts_providers.dart';
import 'package:aja/services/billing/premium_controller.dart';
import 'package:aja/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ids of the saved cards, oldest first.
///
/// Stored as a plain id list in `shared_preferences`: it is a handful of short
/// strings, it is not sensitive, and keeping ids (instead of copies of the
/// cards) means an edited or re-worded fact stays correct in the favourites
/// list after a content update.
final NotifierProvider<FavoritesController, Set<String>> favoritesProvider =
    NotifierProvider<FavoritesController, Set<String>>(FavoritesController.new);

class FavoritesController extends Notifier<Set<String>> {
  static const String _key = 'favorite_fact_ids';

  @override
  Set<String> build() => Set<String>.unmodifiable(
    ref.watch(keyValueStoreProvider).getStringList(_key),
  );

  /// Adds or removes [factId]. Returns true when the card ended up saved.
  ///
  /// Does **not** check the entitlement: the premium gate is a UI decision (it
  /// has to open the paywall, which needs a `BuildContext`), and duplicating it
  /// here would only make the two copies drift.
  Future<bool> toggle(String factId) async {
    final Set<String> next = Set<String>.of(state);
    final bool added = next.add(factId);
    if (!added) next.remove(factId);

    state = Set<String>.unmodifiable(next);
    await ref
        .read(keyValueStoreProvider)
        .setStringList(_key, next.toList(growable: false));

    return added;
  }
}

/// Whether the current user may save cards.
///
/// Favourites are part of the one-off `premium_remove_ads` purchase, so this is
/// the entitlement and nothing else. Named separately from [isPremiumProvider]
/// so that unbundling it later is a one line change here.
final Provider<bool> canUseFavoritesProvider = Provider<bool>(
  (Ref ref) => ref.watch(isPremiumProvider),
);

/// The saved cards resolved against the catalogue, newest first.
///
/// Ids that no longer exist are dropped silently: a content update may retire a
/// fact, and a saved id pointing nowhere must not break the list.
final FutureProvider<List<Fact>> favoriteFactsProvider =
    FutureProvider<List<Fact>>((Ref ref) async {
      final Set<String> ids = ref.watch(favoritesProvider);
      if (ids.isEmpty) return const <Fact>[];

      final List<Fact> all = await ref.watch(factsProvider.future);
      final Map<String, Fact> byId = <String, Fact>{
        for (final Fact fact in all) fact.id: fact,
      };

      return List<Fact>.unmodifiable(
        ids
            .toList(growable: false)
            .reversed
            .map((String id) => byId[id])
            .nonNulls,
      );
    }, isAutoDispose: true);
