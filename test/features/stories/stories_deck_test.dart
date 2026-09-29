/// Rules of the stories deck that hold whether or not there is a server.
///
/// The repository is faked throughout: what is under test is the deck's own
/// behaviour — what it deals, what it remembers, when it asks for more — not
/// Supabase, which is verified against the real project instead.
library;

import 'package:chismosa/core/config/backend_config.dart';
import 'package:chismosa/features/stories/data/seen_stories_store.dart';
import 'package:chismosa/features/stories/data/story_repository.dart';
import 'package:chismosa/features/stories/domain/feed_query.dart';
import 'package:chismosa/features/stories/domain/story.dart';
import 'package:chismosa/features/stories/domain/story_deck.dart';
import 'package:chismosa/features/stories/presentation/providers/stories_deck_controller.dart';
import 'package:chismosa/features/stories/presentation/providers/stories_providers.dart';
import 'package:chismosa/services/billing/premium_controller.dart';
import 'package:chismosa/services/billing/premium_state.dart';
import 'package:chismosa/services/storage/key_value_store.dart';
import 'package:chismosa/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Story _story(String id, {int likes = 0, bool liked = false}) => Story(
  id: id,
  body: 'Historia $id, lo bastante larga para pasar el check.',
  category: StoryCategory.anything,
  lang: 'es',
  createdAt: DateTime.utc(2026, 8, 1),
  likesCount: likes,
  messagesCount: 0,
  liked: liked,
);

/// A repository that serves a fixed catalogue in pages and records what it was
/// asked for.
class _FakeRepository implements StoryRepository {
  _FakeRepository(this.catalogue);

  final List<Story> catalogue;

  final List<String> liked = <String>[];
  final List<String> reported = <String>[];
  final List<List<String>> excludeCalls = <List<String>>[];

  /// Set to make the next fetch throw, as a dead connection would.
  bool failNextFetch = false;

  /// Set to make every like throw.
  bool failLikes = false;

  @override
  Future<List<Story>> fetchFeed(
    FeedQuery query, {
    List<String> excludeIds = const <String>[],
    int limit = BackendConfig.feedPageSize,
  }) async {
    excludeCalls.add(excludeIds);
    if (failNextFetch) {
      failNextFetch = false;
      throw const StoryException(StoryFailure.unknown);
    }
    final Set<String> exclude = excludeIds.toSet();
    return catalogue
        .where((Story story) => !exclude.contains(story.id))
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<PublishStatus> publishStatus() async => const PublishStatus(
    postedToday: 0,
    dailyLimit: 1,
    credits: 0,
    isPremium: false,
  );

  @override
  Future<Story?> fetchStory(String id) async {
    for (final Story story in catalogue) {
      if (story.id == id) return story;
    }
    return null;
  }

  @override
  Future<void> like(String storyId) async {
    if (failLikes) throw const StoryException(StoryFailure.unknown);
    liked.add(storyId);
  }

  @override
  Future<void> unlike(String storyId) async => liked.remove(storyId);

  @override
  Future<List<OwnStory>> myStories() async => const <OwnStory>[];

  @override
  Future<void> report(String storyId, {String? reason}) async =>
      reported.add(storyId);

  @override
  Future<String> publish({
    required String body,
    required StoryCategory category,
    required String lang,
    String? countryCode,
    String? groupId,
    String? parentId,
  }) async => 'new-id';
}

/// Always premium, so no ad slots land in the deck and the assertions can count
/// cards without the AdMob SDK being anywhere near the test.
class _AlwaysPremium extends PremiumController {
  @override
  Future<PremiumStatus> build() async =>
      const PremiumStatus(isPremium: true, storeAvailable: false);
}

List<String> _idsOf(List<StoryDeckItem> items) => items
    .whereType<StoryCard>()
    .map((StoryCard card) => card.story.id)
    .toList(growable: false);

void main() {
  group('buildStoryDeck', () {
    List<Story> stories(int n) =>
        List<Story>.generate(n, (int i) => _story('s$i'));

    test('leaves no slot at all for a premium reader', () {
      final List<StoryDeckItem> deck = buildStoryDeck(
        stories(20),
        withAds: false,
      );
      expect(deck.whereType<StoryAdCard>(), isEmpty);
      expect(deck, hasLength(20));
    });

    test('never ends on an ad', () {
      // A multiple of the interval is the case that would otherwise append a
      // slot as the very last card, which reads as a paywall.
      final List<StoryDeckItem> deck = buildStoryDeck(
        stories(12),
        withAds: true,
      );
      expect(deck.last, isA<StoryCard>());
    });

    test('keeps every card in its original order', () {
      final List<StoryDeckItem> deck = buildStoryDeck(
        stories(15),
        withAds: true,
      );
      expect(_idsOf(deck), _idsOf(buildStoryDeck(stories(15), withAds: false)));
    });

    test(
      'numbers slots on from startSlot so keys stay unique across pages',
      () {
        final List<StoryDeckItem> first = buildStoryDeck(
          stories(13),
          withAds: true,
        );
        final int used = first.whereType<StoryAdCard>().length;
        final List<StoryDeckItem> second = buildStoryDeck(
          stories(13),
          withAds: true,
          startSlot: used,
        );

        final Set<String> keys = <String>{
          ...first.map((StoryDeckItem i) => i.key),
          ...second.map((StoryDeckItem i) => i.key),
        };
        // Story ids repeat between the two pages here; the ad keys must not.
        final Iterable<String> adKeys = <StoryDeckItem>[
          ...first,
          ...second,
        ].whereType<StoryAdCard>().map((StoryAdCard a) => a.key);
        expect(adKeys.toSet(), hasLength(adKeys.length));
        expect(keys, isNotEmpty);
      },
    );
  });

  group('FeedQuery', () {
    test('collapses the catch-all category into no filter', () {
      // "cualquiera" is the shelf for stories that do not have one. Sending it
      // as a filter would hide every story that did pick a category.
      const FeedQuery query = FeedQuery(category: StoryCategory.anything);
      expect(query.categoryParam, isNull);
    });

    test('sends a real category through', () {
      const FeedQuery query = FeedQuery(category: StoryCategory.work);
      expect(query.categoryParam, 'trabajo');
    });

    test('clearing a filter is possible', () {
      const FeedQuery query = FeedQuery(
        category: StoryCategory.love,
        countryCode: 'VE',
      );
      final FeedQuery cleared = query.copyWith(
        category: null,
        countryCode: null,
      );
      expect(cleared.category, isNull);
      expect(cleared.countryCode, isNull);
    });

    test('an untouched field survives copyWith', () {
      const FeedQuery query = FeedQuery(
        category: StoryCategory.love,
        countryCode: 'VE',
      );
      final FeedQuery sorted = query.copyWith(sort: StorySort.newest);
      expect(sorted.category, StoryCategory.love);
      expect(sorted.countryCode, 'VE');
    });
  });

  group('SeenStoriesStore', () {
    late SeenStoriesStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      store = SeenStoriesStore(
        KeyValueStore(await SharedPreferences.getInstance()),
      );
    });

    test('keeps insertion order and drops duplicates', () async {
      await store.add(<String>['a', 'b']);
      final List<String> after = await store.add(<String>['b', 'c']);
      expect(after, <String>['a', 'b', 'c']);
    });

    test('drops the oldest past the cap', () async {
      await store.add(
        List<String>.generate(
          SeenStoriesStore.maxEntries + 10,
          (int i) => '$i',
        ),
      );
      final List<String> kept = store.read();
      expect(kept, hasLength(SeenStoriesStore.maxEntries));
      expect(kept.first, '10');
      expect(kept.last, '${SeenStoriesStore.maxEntries + 9}');
    });
  });

  group('StoriesDeckController', () {
    late _FakeRepository repository;
    late ProviderContainer container;

    Future<void> boot(List<Story> catalogue) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      repository = _FakeRepository(catalogue);
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          premiumControllerProvider.overrideWith(_AlwaysPremium.new),
          storyRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      await container.read(storiesDeckControllerProvider.future);
    }

    StoriesDeckState deck() =>
        container.read(storiesDeckControllerProvider).value!;

    StoriesDeckController controller() =>
        container.read(storiesDeckControllerProvider.notifier);

    test('deals the first page in order', () async {
      await boot(<Story>[_story('a'), _story('b')]);
      expect(_idsOf(deck().items), <String>['a', 'b']);
      expect(deck().index, 0);
    });

    test('a short page means the server is drained', () async {
      await boot(<Story>[_story('a')]);
      expect(deck().drained, isTrue);
    });

    test('passing advances and remembers the card', () async {
      await boot(<Story>[_story('a'), _story('b')]);
      await controller().pass();
      expect(deck().index, 1);
      expect(deck().seenIds, contains('a'));
    });

    test('a card that was passed is not dealt again after a rebuild', () async {
      await boot(<Story>[_story('a'), _story('b')]);
      await controller().pass();

      container.invalidate(storiesDeckControllerProvider);
      await container.read(storiesDeckControllerProvider.future);

      expect(_idsOf(deck().items), <String>['b']);
    });

    test('liking sends the like and drops the card', () async {
      await boot(<Story>[_story('a'), _story('b')]);
      await controller().like();
      expect(repository.liked, <String>['a']);
      expect(deck().index, 1);
      expect(deck().seenIds, contains('a'));
    });

    test('a shake brings the last card back on top', () async {
      await boot(<Story>[_story('a'), _story('b')]);
      await controller().pass();
      expect(controller().undo(), isTrue);
      expect(deck().index, 0);
      expect(deck().current, isA<StoryCard>());
    });

    test('an undone like comes back with the heart filled in', () async {
      await boot(<Story>[_story('a'), _story('b')]);
      await controller().like();
      controller().undo();
      expect((deck().current! as StoryCard).story.liked, isTrue);
    });

    test('nothing to undo on the first card', () async {
      await boot(<Story>[_story('a')]);
      expect(controller().undo(), isFalse);
      expect(deck().index, 0);
    });

    test('a like that fails still advances the deck', () async {
      // The card is off screen by the time the request lands. Rolling back
      // would mean a counter that jumps, which is worse than a lost like.
      await boot(<Story>[_story('a'), _story('b')]);
      repository.failLikes = true;

      await controller().like();

      expect(deck().index, 1);
      expect(deck().seenIds, contains('a'));
    });

    test('entering a thread marks the card and keeps it in place', () async {
      await boot(<Story>[_story('a'), _story('b')]);
      final Story? joined = controller().markTopAsJoined();

      expect(joined?.joined, isTrue);
      // Coming back from a thread onto a different card would make the whole
      // trip feel like a mistake.
      expect(deck().index, 0);
      expect((deck().current! as StoryCard).story.joined, isTrue);
    });

    test('reporting drops the card for this reader immediately', () async {
      await boot(<Story>[_story('a'), _story('b')]);
      await controller().reportTop();
      expect(repository.reported, <String>['a']);
      expect(deck().index, 1);
    });

    test('running low asks for another page and appends it', () async {
      final List<Story> catalogue = List<Story>.generate(
        BackendConfig.feedPageSize * 2,
        (int i) => _story('s$i'),
      );
      await boot(catalogue);
      expect(deck().drained, isFalse);

      // Swipe down to the prefetch threshold.
      const int swipes = BackendConfig.feedPageSize - 3;
      for (int i = 0; i < swipes; i++) {
        await controller().pass();
      }

      expect(deck().items.length, greaterThan(BackendConfig.feedPageSize));
      expect(
        _idsOf(deck().items).toSet(),
        hasLength(_idsOf(deck().items).length),
      );
    });

    test('a failed page is a retry, not an ending', () async {
      final List<Story> catalogue = List<Story>.generate(
        BackendConfig.feedPageSize * 2,
        (int i) => _story('s$i'),
      );
      await boot(catalogue);

      repository.failNextFetch = true;
      for (int i = 0; i < BackendConfig.feedPageSize - 3; i++) {
        await controller().pass();
      }

      expect(deck().drained, isFalse);
      expect(deck().loadingMore, isFalse);
    });

    test('restarting forgets the read pile and deals it all again', () async {
      await boot(<Story>[_story('a'), _story('b')]);
      await controller().pass();
      await controller().pass();
      expect(deck().isExhausted, isTrue);

      await controller().restart();
      await container.read(storiesDeckControllerProvider.future);

      expect(_idsOf(deck().items), <String>['a', 'b']);
      expect(deck().seenIds, isEmpty);
    });

    test('no client yet is a wait, never an ending', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          premiumControllerProvider.overrideWith(_AlwaysPremium.new),
          storyRepositoryProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      await container.read(storiesDeckControllerProvider.future);

      final StoriesDeckState state = container
          .read(storiesDeckControllerProvider)
          .value!;
      expect(state.isWaiting, isTrue);
      expect(state.isExhausted, isFalse);
    });
  });
}
