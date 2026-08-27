import 'package:aja/features/facts/data/fact_repository.dart';
import 'package:aja/features/facts/data/fact_share_service.dart';
import 'package:aja/features/facts/data/remote_catalog_service.dart';
import 'package:aja/features/facts/domain/fact.dart';
import 'package:aja/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Downloads and caches the catalogue published after the app shipped.
///
/// Kept alive: it owns an `http.Client`, and the refresh it runs after the
/// first frame must not be cancelled by a screen going away.
final Provider<RemoteCatalogService> remoteCatalogServiceProvider =
    Provider<RemoteCatalogService>((Ref ref) {
      final RemoteCatalogService service = RemoteCatalogService(
        ref.watch(keyValueStoreProvider),
      );
      ref.onDispose(service.dispose);
      return service;
    });

/// Holds the parsed catalogue for the process lifetime, so switching category
/// or restarting the deck never re-reads the asset.
///
/// The repository reads the downloaded overlay **from disk**, never from the
/// network: this is on the path to the first screen.
final Provider<FactRepository> factRepositoryProvider =
    Provider<FactRepository>(
      (Ref ref) => FactRepository(
        overlay: ref.watch(remoteCatalogServiceProvider).readCache,
      ),
    );

/// The whole catalogue, unfiltered. Read-only, so `autoDispose` is correct: the
/// repository cache is what makes a re-subscription free.
final FutureProvider<List<Fact>> factsProvider = FutureProvider<List<Fact>>(
  (Ref ref) => ref.watch(factRepositoryProvider).loadAll(),
  isAutoDispose: true,
);

/// Stateless plumbing around the OS share sheet, so a plain [Provider].
final Provider<FactShareService> factShareServiceProvider =
    Provider<FactShareService>((Ref ref) => const FactShareService());

/// Selected category, or `null` for "all". Kept out of the deck state so that
/// picking a category simply rebuilds the deck instead of mutating it in place.
final NotifierProvider<FactCategoryFilter, FactCategory?>
categoryFilterProvider = NotifierProvider<FactCategoryFilter, FactCategory?>(
  FactCategoryFilter.new,
);

class FactCategoryFilter extends Notifier<FactCategory?> {
  @override
  FactCategory? build() => null;

  void select(FactCategory? category) => state = category;
}

/// Fact hoisted to the top of the deck, set when the user opens the app from a
/// daily-question notification.
///
/// Deliberately **not persisted** and deliberately not part of [DeckState]: it
/// belongs to one session, and a pin that survived a restart would keep pulling
/// the same card forward days later. It clears itself when the process dies.
final NotifierProvider<PinnedFact, String?> pinnedFactProvider =
    NotifierProvider<PinnedFact, String?>(PinnedFact.new);

class PinnedFact extends Notifier<String?> {
  @override
  String? build() => null;

  void pin(String factId) => state = factId;

  void clear() => state = null;
}
