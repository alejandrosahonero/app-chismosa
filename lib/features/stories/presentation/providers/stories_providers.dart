import 'package:chismosa/features/stories/data/seen_stories_store.dart';
import 'package:chismosa/features/stories/data/story_repository.dart';
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
    // The languages come from preferences and the country does not: the deck is
    // worldwide by default, because "stories from everywhere" is the product.
    // Filtering by country is something the reader turns on.
    return FeedQuery(languages: locale.languages);
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
