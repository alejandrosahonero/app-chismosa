import 'package:chismosa/features/stories/data/seen_stories_store.dart';
import 'package:chismosa/features/stories/data/story_repository.dart';
import 'package:chismosa/features/stories/data/story_share_service.dart';
import 'package:chismosa/features/stories/domain/feed_query.dart';
import 'package:chismosa/features/stories/domain/story.dart';
import 'package:chismosa/services/backend/backend_providers.dart';
import 'package:chismosa/services/locale/locale_providers.dart';
import 'package:chismosa/services/locale/locale_settings.dart';
import 'package:chismosa/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The repository, or null while there is no client.
///
/// Null rather than a throwing provider: the client only exists after the first
/// frame, and the deck has a perfectly good thing to show in the meantime.
final Provider<StoryRepository?> storyRepositoryProvider =
    Provider<StoryRepository?>((Ref ref) {
      ref.watch(sessionEpochProvider);
      final SupabaseClient? client = ref.watch(supabaseClientProvider);
      if (client == null) return null;
      return SupabaseStoryRepository(client);
    });

final Provider<SeenStoriesStore> seenStoriesStoreProvider =
    Provider<SeenStoriesStore>(
      (Ref ref) => SeenStoriesStore(ref.watch(keyValueStoreProvider)),
    );

/// What the deck is currently asking for.
///
/// Kept out of the deck state so that changing a filter rebuilds the deck
/// instead of mutating it: a half-changed deck — new category, old cards — is
/// the bug this shape makes impossible.
final NotifierProvider<FeedQueryController, FeedQuery> feedQueryProvider =
    NotifierProvider<FeedQueryController, FeedQuery>(FeedQueryController.new);

class FeedQueryController extends Notifier<FeedQuery> {
  @override
  FeedQuery build() {
    final LocaleSettings locale = ref.watch(localeSettingsProvider);
    // Starts on the phone's own country (see [FeedQuery.countryCode]); the
    // reader widens it from the chip or from the "nothing left" screen.
    return FeedQuery(
      languages: locale.languages,
      countryCode: locale.countryCode,
    );
  }

  void selectCategory(StoryCategory? category) =>
      state = state.copyWith(category: category);

  void selectSort(StorySort sort) => state = state.copyWith(sort: sort);

  /// null goes back to the worldwide deck.
  void selectCountry(String? countryCode) =>
      state = state.copyWith(countryCode: countryCode);

  /// null goes back to the worldwide deck; an id restricts it to one group.
  void selectGroup(String? groupId) => state = state.copyWith(groupId: groupId);
}

/// Today's publishing quota, for the compose screen.
///
/// Re-read on every visit, and invalidated after a publish or a rewarded
/// video: it is a snapshot of the server, and a stale "you have 1 left" is the
/// one thing that screen must not say.
final FutureProvider<PublishStatus?> publishStatusProvider =
    FutureProvider<PublishStatus?>((Ref ref) async {
      final StoryRepository? repository = ref.watch(storyRepositoryProvider);
      if (repository == null) return null;
      return repository.publishStatus();
    }, isAutoDispose: true);

/// The reader's own stories, for "Mis historias".
final FutureProvider<List<OwnStory>> myStoriesProvider =
    FutureProvider<List<OwnStory>>((Ref ref) async {
      final StoryRepository? repository = ref.watch(storyRepositoryProvider);
      if (repository == null) return const <OwnStory>[];
      return repository.myStories();
    }, isAutoDispose: true);

/// Kept alive: it holds the guard against two share sheets at once.
final Provider<StoryShareService> storyShareServiceProvider =
    Provider<StoryShareService>((Ref ref) => StoryShareService());

/// Everything the reader liked, newest like first, for the "Me gusta" list.
///
/// The same `feed(p_liked)` query the deck understands, as a list: a deck is
/// for reading once, a list is for finding one again.
final FutureProvider<List<Story>> likedStoriesProvider =
    FutureProvider<List<Story>>((Ref ref) async {
      final StoryRepository? repository = ref.watch(storyRepositoryProvider);
      if (repository == null) return const <Story>[];
      return repository.fetchFeed(
        const FeedQuery(liked: true),
        limit: likedHistoryLimit,
      );
    }, isAutoDispose: true);

/// How many liked stories the list shows. One page, no paging: past a couple
/// of hundred, nobody is scrolling to find one.
const int likedHistoryLimit = 200;
