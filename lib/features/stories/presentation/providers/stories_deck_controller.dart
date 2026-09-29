import 'dart:async';

import 'package:chismosa/core/config/app_config.dart';
import 'package:chismosa/core/config/backend_config.dart';
import 'package:chismosa/core/utils/app_logger.dart';
import 'package:chismosa/features/stories/data/seen_stories_store.dart';
import 'package:chismosa/features/stories/data/story_repository.dart';
import 'package:chismosa/features/stories/domain/feed_query.dart';
import 'package:chismosa/features/stories/domain/story.dart';
import 'package:chismosa/features/stories/domain/story_deck.dart';
import 'package:chismosa/features/stories/presentation/providers/stories_providers.dart';
import 'package:chismosa/services/billing/premium_controller.dart';
import 'package:chismosa/services/moderation/moderation_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Everything the deck needs to paint one frame.
@immutable
class StoriesDeckState {
  const StoriesDeckState({
    required this.items,
    required this.index,
    required this.seenIds,
    this.loadingMore = false,
    this.drained = false,
  });

  static const StoriesDeckState empty = StoriesDeckState(
    items: <StoryDeckItem>[],
    index: 0,
    seenIds: <String>[],
    drained: true,
  );

  final List<StoryDeckItem> items;

  /// Position of the top card. Equal to `items.length` once the pile is spent.
  final int index;

  /// Cards this device has already dealt, oldest first.
  final List<String> seenIds;

  /// A page is in flight. The deck keeps working while it is: the whole point
  /// of fetching early is that the reader never waits.
  final bool loadingMore;

  /// The server has nothing else to offer for this query. Distinct from "the
  /// pile is empty right now", which is a loading state, not an ending.
  final bool drained;

  StoryDeckItem? get current => index >= items.length ? null : items[index];

  int get remaining => items.length - index;

  /// Nothing left and nothing coming. The only state that gets a screen of its
  /// own instead of a card.
  bool get isExhausted => remaining <= 0 && drained && !loadingMore;

  /// Nothing to show yet, but something is on its way.
  bool get isWaiting => remaining <= 0 && !isExhausted;

  StoriesDeckState copyWith({
    List<StoryDeckItem>? items,
    int? index,
    List<String>? seenIds,
    bool? loadingMore,
    bool? drained,
  }) => StoriesDeckState(
    items: items ?? this.items,
    index: index ?? this.index,
    seenIds: seenIds ?? this.seenIds,
    loadingMore: loadingMore ?? this.loadingMore,
    drained: drained ?? this.drained,
  );
}

final AsyncNotifierProvider<StoriesDeckController, StoriesDeckState>
storiesDeckControllerProvider =
    AsyncNotifierProvider<StoriesDeckController, StoriesDeckState>(
      StoriesDeckController.new,
    );

/// Owns the pile: which card is on top, which ones this device has seen, and
/// when to ask the server for more.
///
/// Deliberately free of ad, review and navigation calls. Those are
/// orchestration and belong to the screen, which is the only place that knows a
/// swipe was a real finger rather than a state restore.
class StoriesDeckController extends AsyncNotifier<StoriesDeckState> {
  @override
  Future<StoriesDeckState> build() async {
    final FeedQuery query = ref.watch(feedQueryProvider);

    // `watch` and not `read`: buying premium must strip the ad slots out of the
    // deck the reader is holding, not only out of the next one.
    final bool isPremium = ref.watch(isPremiumProvider);

    final StoryRepository? repository = ref.watch(storyRepositoryProvider);
    final SeenStoriesStore seen = ref.read(seenStoriesStoreProvider);
    final List<String> seenIds = seen.read();

    // No client yet — sign-in happens after the first frame — so this is a
    // "not yet", not an ending. `drained: false` is what keeps the screen on
    // its loading state instead of announcing that the world ran out of gossip.
    if (repository == null) {
      return StoriesDeckState(
        items: const <StoryDeckItem>[],
        index: 0,
        seenIds: seenIds,
      );
    }

    // Bounded: an unreachable server (no DNS, a paused project, a captive
    // portal) otherwise leaves the deck on its spinner forever. Timing out
    // turns it into the offline screen, which has a retry button.
    final List<Story> page = await repository
        .fetchFeed(
          query,
          excludeIds: seenIds,
          limit: BackendConfig.feedPageSize,
        )
        .timeout(BackendConfig.requestTimeout);

    // "Me gustaron" is the one mode that re-deals seen cards.
    final List<Story> fresh = query.liked
        ? page
        : _withoutSeen(page, seenIds.toSet());

    return StoriesDeckState(
      items: buildStoryDeck(fresh, withAds: !isPremium && !kIsWeb),
      index: 0,
      seenIds: seenIds,
      drained: page.length < BackendConfig.feedPageSize,
    );
  }

  /// Left swipe, or down: not for me, next.
  Future<void> pass() => _consumeTop();

  /// Right swipe: like it, then next.
  ///
  /// The like is applied to the card **before** the request goes out and is not
  /// rolled back if it fails. The card is already flying off screen by then, so
  /// there is nothing left to correct on; a lost like is a rounding error, and
  /// a counter that jumps back a frame later is a bug the reader can see.
  Future<void> like() async {
    final StoriesDeckState? current = state.value;
    final StoryDeckItem? top = current?.current;
    if (current == null || top is! StoryCard) return;

    // Marked liked before it leaves, so a shake brings it back with the heart
    // filled in and "Me gustaron" already knows about it.
    _replaceTop(top.story.withLike(liked: true));
    await _consumeTop();

    if (top.story.liked) return;
    try {
      await ref.read(storyRepositoryProvider)?.like(top.story.id);
      ref.invalidate(likedStoriesProvider);
    } on Object catch (error) {
      AppLogger.debug('Like failed: $error', name: 'stories');
    }
  }

  /// Up swipe: hand the top story over so the thread panel can open it.
  ///
  /// The join itself belongs to the thread controller — it is the one that
  /// needs the membership back, because a message points at it. All this does
  /// is mark the card so the footer stops saying the reader is a stranger to
  /// the conversation.
  ///
  /// The card is **not** consumed. Coming back from a thread onto a different
  /// card would make the whole trip feel like a mistake.
  Story? markTopAsJoined() {
    final StoryDeckItem? top = state.value?.current;
    if (top is! StoryCard) return null;

    final Story joined = top.story.copyWith(joined: true);
    _replaceTop(joined);
    return joined;
  }

  /// Reports the top card and drops it.
  ///
  /// It disappears for this reader whatever the server decides: somebody who
  /// just reported a story should not have to look at it while three other
  /// people make up their minds.
  Future<void> reportTop({String? reason}) async {
    final StoryDeckItem? top = state.value?.current;
    if (top is! StoryCard) return;

    await _consumeTop();
    try {
      await ref
          .read(storyRepositoryProvider)
          ?.report(top.story.id, reason: reason);
    } on Object catch (error) {
      AppLogger.debug('Report failed: $error', name: 'stories');
    }
  }

  /// Blocks whoever wrote the top story, then deals the pile again.
  ///
  /// Re-dealing rather than just dropping the card: the same author may have
  /// more stories further down the pile already fetched, and the point of a
  /// block is that none of them ever shows up. The server leaves them out of
  /// the new page; the read pile keeps everything already swiped out of it.
  Future<void> blockTopAuthor() async {
    final StoryDeckItem? top = state.value?.current;
    if (top is! StoryCard) return;

    final ModerationService? moderation = ref.read(moderationServiceProvider);
    if (moderation == null) return;

    await moderation.blockStoryAuthor(top.story.id);
    await ref.read(seenStoriesStoreProvider).add(<String>[top.story.id]);
    ref.invalidateSelf();
  }

  /// Shake: puts the last story the reader swiped away back on top.
  ///
  /// Ad slots on the way back are skipped — nobody shakes the phone to see an
  /// ad again. The card stays in the seen list: it has been dealt, and undoing
  /// is about this pile, not about the next session's. A like already sent is
  /// kept; the card comes back showing it.
  ///
  /// Returns whether there was anything to bring back.
  bool undo() {
    final StoriesDeckState? current = state.value;
    if (current == null) return false;

    for (int i = current.index - 1; i >= 0; i--) {
      if (current.items[i] is StoryCard) {
        state = AsyncData<StoriesDeckState>(current.copyWith(index: i));
        return true;
      }
    }
    return false;
  }

  /// Asks the server for stories this device has not seen yet and adds them to
  /// the end of the pile. Returns how many arrived.
  ///
  /// Appended, never a rebuild: the card on top stays where it is, and a
  /// shake still brings back the one before it. Used by "Buscar historias
  /// nuevas", by the pull-down on the "nothing left" screen, and when the app
  /// comes back after a while (the deck screen decides when).
  Future<int> refresh() async {
    final int before = state.value?.items.length ?? 0;
    await _topUp(force: true);
    final int after = state.value?.items.length ?? 0;
    return after - before;
  }

  /// Forgets every card this device has been dealt and starts over.
  ///
  /// The only honest answer to a reader who has genuinely read everything: the
  /// alternative is an empty screen until somebody, somewhere, writes something.
  Future<void> restart() async {
    await ref.read(seenStoriesStoreProvider).clear();
    ref.invalidateSelf();
  }

  /// Drops the top card, marks it seen and tops the pile up if it is running
  /// low.
  Future<void> _consumeTop() async {
    final StoriesDeckState? current = state.value;
    final StoryDeckItem? top = current?.current;
    if (current == null || top == null) return;

    StoriesDeckState next = current.copyWith(index: current.index + 1);

    if (top is StoryCard) {
      final List<String> seenIds = await ref.read(seenStoriesStoreProvider).add(
        <String>[top.story.id],
      );
      next = next.copyWith(seenIds: seenIds);
    }

    state = AsyncData<StoriesDeckState>(next);
    unawaited(_topUp());
  }

  /// Appends the next page once the pile gets short.
  ///
  /// Appending rather than replacing is what keeps the deck seamless: the cards
  /// the reader has not reached stay exactly where they were, and the ad slot
  /// numbering carries on from where the last page left it so two slots never
  /// share a widget key.
  ///
  /// [force] asks even when the server said it was drained or the pile is still
  /// long: new stories may have been written since.
  Future<void> _topUp({bool force = false}) async {
    final StoriesDeckState? current = state.value;
    if (current == null || current.loadingMore) return;
    if (!force &&
        (current.drained ||
            current.remaining > AppConfig.deckPrefetchThreshold)) {
      return;
    }

    final StoryRepository? repository = ref.read(storyRepositoryProvider);
    if (repository == null) return;

    state = AsyncData<StoriesDeckState>(current.copyWith(loadingMore: true));

    try {
      final FeedQuery query = ref.read(feedQueryProvider);
      final List<Story> page = await repository.fetchFeed(
        query,
        // The liked list is paged by what is already in the pile, not by the
        // seen list — every card in it has been seen.
        excludeIds: query.liked
            ? current.items
                  .whereType<StoryCard>()
                  .map((StoryCard c) => c.story.id)
                  .toList(growable: false)
            : current.seenIds,
        limit: BackendConfig.feedPageSize,
      );

      final StoriesDeckState now = state.value ?? current;
      final Set<String> known = <String>{
        if (!query.liked) ...now.seenIds,
        ...now.items.whereType<StoryCard>().map((StoryCard c) => c.story.id),
      };

      final List<Story> fresh = _withoutSeen(page, known);
      final int slots = now.items.whereType<StoryAdCard>().length;

      state = AsyncData<StoriesDeckState>(
        now.copyWith(
          items: <StoryDeckItem>[
            ...now.items,
            ...buildStoryDeck(
              fresh,
              withAds: !ref.read(isPremiumProvider) && !kIsWeb,
              startSlot: slots,
            ),
          ],
          loadingMore: false,
          drained: page.length < BackendConfig.feedPageSize,
        ),
      );
    } on Object catch (error) {
      AppLogger.debug('Feed page failed: $error', name: 'stories');
      // Not `drained`: a failed request is a retry, not an ending. The next
      // swipe asks again.
      state = AsyncData<StoriesDeckState>(
        (state.value ?? current).copyWith(loadingMore: false),
      );
    }
  }

  /// Swaps the story on the top card, keeping its position.
  void _replaceTop(Story story) {
    final StoriesDeckState? current = state.value;
    if (current == null || current.current is! StoryCard) return;

    final List<StoryDeckItem> items = List<StoryDeckItem>.of(current.items);
    items[current.index] = StoryCard(story);
    state = AsyncData<StoriesDeckState>(current.copyWith(items: items));
  }

  /// The server already filters by the exclusion hint, but only the tail of it
  /// fits in a request. This is the half of the filter that is complete.
  static List<Story> _withoutSeen(List<Story> page, Set<String> seen) => page
      .where((Story story) => !seen.contains(story.id))
      .toList(growable: false);
}
