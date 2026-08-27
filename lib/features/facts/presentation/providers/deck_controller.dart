import 'dart:math';

import 'package:aja/features/facts/domain/deck_item.dart';
import 'package:aja/features/facts/domain/fact.dart';
import 'package:aja/features/facts/presentation/providers/facts_providers.dart';
import 'package:aja/services/billing/premium_controller.dart';
import 'package:aja/services/storage/key_value_store.dart';
import 'package:aja/services/storage/storage_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Everything the deck needs to paint one frame.
///
/// [revealed] lives here rather than inside the card widget so the card stays a
/// pure function of the state: a swipe, a tap and a restore-from-storage all go
/// through the same path, and the flip is testable without pumping an
/// animation.
@immutable
class DeckState {
  const DeckState({
    required this.items,
    required this.index,
    required this.seenIds,
    required this.revealed,
  });

  /// Only cards the user has not read yet, plus whatever the notification
  /// pinned. A card leaves this list for good the moment it is swiped away.
  final List<DeckItem> items;

  /// Position of the top card. Equal to `items.length` when the deck is spent.
  final int index;

  /// Ids of every fact already swiped away, across every category filter.
  ///
  /// One shared set rather than a per-filter counter: the filters are four
  /// views of one catalogue, so reading all of "Ciencia" and then switching to
  /// "Todas" must not deal those same cards again.
  final Set<String> seenIds;

  /// Whether the top card shows its back.
  final bool revealed;

  bool get isExhausted => index >= items.length;

  DeckItem? get current => isExhausted ? null : items[index];

  DeckState copyWith({
    List<DeckItem>? items,
    int? index,
    Set<String>? seenIds,
    bool? revealed,
  }) => DeckState(
    items: items ?? this.items,
    index: index ?? this.index,
    seenIds: seenIds ?? this.seenIds,
    revealed: revealed ?? this.revealed,
  );
}

final AsyncNotifierProvider<DeckController, DeckState> deckControllerProvider =
    AsyncNotifierProvider<DeckController, DeckState>(DeckController.new);

/// Owns the card stack: which card is on top, whether it is flipped, and which
/// cards the user has already read.
///
/// Deliberately free of ad and review calls. Those are orchestration and belong
/// to the screen, which is the only place that knows a swipe was a real user
/// gesture rather than a state restore.
class DeckController extends AsyncNotifier<DeckState> {
  /// Ids of every fact read so far, for **all** filters at once.
  ///
  /// Storing ids and not a count is what makes the category chips consistent
  /// with each other. A count only means something against one fixed ordering,
  /// so the old per-filter counters could not tell "Todas" that the twenty-three
  /// science cards in it had already been read under the "Ciencia" chip — and
  /// dealing a card the user just finished reading is the one thing the deck
  /// must never do.
  ///
  /// The list rides along in `SharedPreferences`, which loads whole at startup
  /// (§10), so it is worth knowing it grows with the catalogue: at 533 entries
  /// this is on the order of ten kilobytes. Ids of facts dropped by a remote
  /// catalogue update simply stop matching anything and are harmless.
  static const String _seenIdsKey = 'deck_seen_ids';

  static const String _seedKeyPrefix = 'deck_shuffle_seed_';

  /// Seed meaning "leave the catalogue alone".
  ///
  /// The first run through a category is the curated order: the file is
  /// interleaved by hand so the categories rotate, and shuffling that on a
  /// user's very first session throws away the only editorial control there is
  /// over which question they meet first. Only [restart] shuffles.
  static const int _curatedOrder = 0;

  @override
  Future<DeckState> build() async {
    final List<Fact> all = await ref.watch(factsProvider.future);
    final FactCategory? category = ref.watch(categoryFilterProvider);

    // `watch`: buying premium must remove the ad slots from the deck already
    // built, not only from the next one.
    final bool isPremium = ref.watch(isPremiumProvider);
    final KeyValueStore store = ref.read(keyValueStoreProvider);

    return _deckFor(
      all: all,
      category: category,
      isPremium: isPremium,
      seed: store.getInt(_seedKey(category)),
      seenIds: store.getStringList(_seenIdsKey).toSet(),
      pinnedFactId: ref.watch(pinnedFactProvider),
    );
  }

  /// Builds the deck for one (category, seed, read-pile) triple.
  ///
  /// Shared by [build] and [restart] so a restarted deck cannot drift from a
  /// rebuilt one: the same seed must always produce the same order, otherwise
  /// buying premium mid-deck would reshuffle the cards under the user.
  ///
  /// The deck holds **only unread cards**, so the top of the deck is always
  /// index 0 and a rebuild cannot land the user on a card they already read.
  /// That is also why there is no longer a stored position to translate: the
  /// read pile is identified by id, so it survives the ad slots moving when the
  /// user buys premium, and it survives changing the category filter.
  DeckState _deckFor({
    required List<Fact> all,
    required FactCategory? category,
    required bool isPremium,
    required int seed,
    required Set<String> seenIds,
    String? pinnedFactId,
  }) {
    final List<Fact> inFilter = category == null
        ? all
        : all.where((Fact fact) => fact.category == category).toList();

    final List<Fact> ordered = seed == _curatedOrder
        ? inFilter
        : (List<Fact>.of(inFilter)..shuffle(Random(seed)));

    final List<Fact> unread = ordered
        .where((Fact fact) => !seenIds.contains(fact.id))
        .toList();

    final List<Fact> dealt = _hoist(unread, ordered, pinnedFactId);

    return DeckState(
      items: buildDeck(dealt, withAds: !isPremium),
      index: 0,
      seenIds: seenIds,
      revealed: false,
    );
  }

  /// Puts [pinnedFactId] on top, keeping everything else in order.
  ///
  /// This is what makes the daily notification safe to tap. The pinned card is
  /// lifted out of wherever it sits and dropped in front of the user, and the
  /// cards it was sitting among close the gap behind it. Whatever was going to
  /// come next still comes next, one place later — nothing is skipped.
  ///
  /// A card the user already read works too: it is not in [unread] at all, so
  /// it is taken from [pool] and put back on top for this session. Swiping it
  /// away simply marks it read again, which is a no-op.
  ///
  /// Off the end of a spent deck it still works: the pinned card becomes the
  /// whole deck, and the deck is finished again right after it — the correct
  /// behaviour for a reminder tapped by somebody who already read everything.
  static List<Fact> _hoist(
    List<Fact> unread,
    List<Fact> pool,
    String? pinnedFactId,
  ) {
    if (pinnedFactId == null) return unread;

    final int at = pool.indexWhere((Fact fact) => fact.id == pinnedFactId);
    // Unknown id, or filtered out by the category chips: the deck is left
    // exactly as it was rather than guessing what the user meant.
    if (at < 0) return unread;

    return <Fact>[
      pool[at],
      ...unread.where((Fact fact) => fact.id != pinnedFactId),
    ];
  }

  /// Right swipe / tap: show the other side of the card.
  void toggleReveal() {
    final DeckState? current = state.value;
    if (current == null || current.isExhausted) return;
    // Ad cards have no back side.
    if (current.current is! FactItem) return;

    state = AsyncData<DeckState>(current.copyWith(revealed: !current.revealed));
  }

  /// Left swipe: drop the top card and bring up the next one.
  ///
  /// Returns the item that was dismissed so the caller can decide whether it
  /// was a value moment worth counting for ads and reviews.
  Future<DeckItem?> next() async {
    final DeckState? current = state.value;
    if (current == null || current.isExhausted) return null;

    final DeckItem dismissed = current.items[current.index];
    if (dismissed is! FactItem) {
      state = AsyncData<DeckState>(
        current.copyWith(index: current.index + 1, revealed: false),
      );
      return dismissed;
    }

    final Set<String> seenIds = <String>{...current.seenIds, dismissed.fact.id};

    state = AsyncData<DeckState>(
      current.copyWith(
        index: current.index + 1,
        seenIds: seenIds,
        revealed: false,
      ),
    );

    await _persistSeen(seenIds);
    return dismissed;
  }

  /// Back to a full deck of the current filter, **in a new order**.
  ///
  /// A reshuffle rather than a rewind: somebody who reaches the end and presses
  /// restart is asking for more, and handing them the same cards in the same
  /// sequence answers that with "no". The seed is persisted so the new order
  /// survives closing the app — a deck that reshuffles itself every time the
  /// screen rebuilds would lose the user's place instead of keeping it.
  ///
  /// Only the cards **in the current filter** are marked unread again. Pressing
  /// restart under the "Ciencia" chip is a request for more science, not an
  /// offer to re-read the history the user finished last week.
  Future<void> restart() async {
    if (state.value == null) return;

    final FactCategory? category = ref.read(categoryFilterProvider);
    final KeyValueStore store = ref.read(keyValueStoreProvider);
    final int seed = _nextSeed(store.getInt(_seedKey(category)));

    // Already resolved and cached; this does not hit the asset again.
    final List<Fact> all = await ref.read(factsProvider.future);
    final Set<String> revived = all
        .where((Fact fact) => category == null || fact.category == category)
        .map((Fact fact) => fact.id)
        .toSet();
    final Set<String> seenIds = state.value!.seenIds.difference(revived);

    await store.setInt(_seedKey(category), seed);
    await _persistSeen(seenIds);

    state = AsyncData<DeckState>(
      _deckFor(
        all: all,
        category: category,
        isPremium: ref.read(isPremiumProvider),
        seed: seed,
        seenIds: seenIds,
      ),
    );
  }

  /// A seed that is neither the curated order nor the one just used, so
  /// "restart" always visibly changes something.
  static int _nextSeed(int previous) {
    final Random random = Random();
    int seed = previous;
    while (seed == previous || seed == _curatedOrder) {
      seed = random.nextInt(0x7FFFFFFF);
    }
    return seed;
  }

  Future<void> _persistSeen(Set<String> seenIds) => ref
      .read(keyValueStoreProvider)
      .setStringList(_seenIdsKey, seenIds.toList(growable: false));

  static String _seedKey(FactCategory? category) =>
      '$_seedKeyPrefix${category?.id ?? 'all'}';
}
