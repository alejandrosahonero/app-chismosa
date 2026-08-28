import 'package:chismosa/core/config/backend_config.dart';
import 'package:chismosa/features/stories/domain/feed_query.dart';
import 'package:chismosa/features/stories/domain/story.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Why the server refused something, in terms the UI can act on.
///
/// The rules live in Postgres triggers (see `0002_logic.sql`) because a limit
/// the client enforces is a limit that does not exist. The cost of that is this
/// enum: the only thing that reaches Dart is a string, so it has to be mapped
/// back into something with a message attached.
enum StoryFailure {
  /// One story a day is spent. Watching an ad buys another.
  dailyLimitReached,

  /// The account crossed the moderation threshold and cannot publish.
  accountBanned,

  /// The text tripped the word filter.
  blockedContent,

  /// Publishing into a group the user is not in.
  notAGroupMember,

  /// The story is gone — hidden by reports, or its author was banned.
  storyUnavailable,

  /// Messages only: the thread was closed for inactivity.
  threadClosed,

  /// Messages only: too many, too fast.
  tooFast,

  /// No session yet. Sign-in runs after the first frame, so this is reachable
  /// by a user who is very quick, and by anyone with no connection.
  notAuthenticated,

  /// Anything else: no network, a 500, a schema change this build predates.
  unknown;

  static StoryFailure fromCode(String? code) => switch (code) {
    'daily_limit_reached' => StoryFailure.dailyLimitReached,
    'account_banned' => StoryFailure.accountBanned,
    'blocked_content' => StoryFailure.blockedContent,
    'not_a_group_member' => StoryFailure.notAGroupMember,
    'story_unavailable' => StoryFailure.storyUnavailable,
    'thread_closed' => StoryFailure.threadClosed,
    'too_fast' => StoryFailure.tooFast,
    'not_authenticated' => StoryFailure.notAuthenticated,
    _ => StoryFailure.unknown,
  };
}

/// Thrown by [StoryRepository] when the server says no.
class StoryException implements Exception {
  const StoryException(this.failure, [this.detail]);

  final StoryFailure failure;

  /// Raw server text. For the log, never for the screen: it is English, it is
  /// unlocalized, and it names tables.
  final String? detail;

  @override
  String toString() => 'StoryException(${failure.name}, $detail)';
}

/// Everything the deck asks of the server.
///
/// An interface and not just the Supabase class so the deck controller can be
/// tested without a network, a project or a session — which is the difference
/// between testing the deck's rules and testing Supabase.
abstract interface class StoryRepository {
  /// One page of the deck.
  ///
  /// [excludeIds] is the tail of the device's seen list, sent as a hint so a
  /// page is not wasted on cards the reader already swiped. It is not the
  /// source of truth: the caller filters the result again.
  Future<List<Story>> fetchFeed(
    FeedQuery query, {
    List<String> excludeIds = const <String>[],
    int limit = BackendConfig.feedPageSize,
  });

  /// One story by id, for a deep link or a row in the thread history.
  Future<Story?> fetchStory(String id);

  Future<void> like(String storyId);

  Future<void> unlike(String storyId);

  /// Publishes a story. Returns its id.
  ///
  /// Everything that can refuse this — the daily quota, the ban, the word
  /// filter, group membership — is checked by a trigger, so a success here
  /// means the row exists.
  Future<String> publish({
    required String body,
    required StoryCategory category,
    required String lang,
    String? countryCode,
    String? groupId,
  });

  Future<void> report(String storyId, {String? reason});
}

/// [StoryRepository] against Supabase.
///
/// Every read goes through an RPC rather than a table select. That is not
/// ceremony: `stories` has no public SELECT policy at all, precisely so that
/// no query the client can write is able to ask for `author_id`.
class SupabaseStoryRepository implements StoryRepository {
  const SupabaseStoryRepository(this._client);

  final SupabaseClient _client;

  String get _userId {
    final String? id = _client.auth.currentUser?.id;
    if (id == null) throw const StoryException(StoryFailure.notAuthenticated);
    return id;
  }

  @override
  Future<List<Story>> fetchFeed(
    FeedQuery query, {
    List<String> excludeIds = const <String>[],
    int limit = BackendConfig.feedPageSize,
  }) async {
    // Only the newest ids travel. The whole list can be thousands of entries
    // after a few weeks of use, and the ones that matter for the next page are
    // the recent ones — an old id is unlikely to come back up a hot feed.
    final List<String> exclude =
        excludeIds.length <= BackendConfig.seenIdsSentWithFeed
        ? excludeIds
        : excludeIds.sublist(
            excludeIds.length - BackendConfig.seenIdsSentWithFeed,
          );

    final List<Map<String, dynamic>> rows =
        await _rpcRows('feed', <String, dynamic>{
          'p_group': query.groupId,
          'p_category': query.categoryParam,
          'p_langs': query.languagesParam,
          'p_country': query.countryCode,
          'p_sort': query.sort.id,
          'p_exclude': exclude,
          'p_limit': limit,
        });

    return rows.map(Story.fromRow).toList(growable: false);
  }

  @override
  Future<Story?> fetchStory(String id) async {
    final List<Map<String, dynamic>> rows = await _rpcRows(
      'story_detail',
      <String, dynamic>{'p_story': id},
    );
    return rows.isEmpty ? null : Story.fromRow(rows.first);
  }

  @override
  Future<void> like(String storyId) => _guard(
    () => _client.from('story_likes').insert(<String, dynamic>{
      'story_id': storyId,
      'user_id': _userId,
    }),
  );

  @override
  Future<void> unlike(String storyId) => _guard(
    () => _client
        .from('story_likes')
        .delete()
        .eq('story_id', storyId)
        .eq('user_id', _userId),
  );

  @override
  Future<String> publish({
    required String body,
    required StoryCategory category,
    required String lang,
    String? countryCode,
    String? groupId,
  }) async {
    final Map<String, dynamic> row = await _guard(
      () => _client
          .from('stories')
          .insert(<String, dynamic>{
            'author_id': _userId,
            'body': body,
            'category': category.id,
            'lang': lang,
            'country_code': countryCode,
            'group_id': groupId,
          })
          .select('id')
          .single(),
    );
    return row['id']! as String;
  }

  @override
  Future<void> report(String storyId, {String? reason}) => _guard(
    () => _client.rpc<void>(
      'report_content',
      params: <String, dynamic>{
        'p_target_type': 'story',
        'p_target_id': storyId,
        'p_reason': reason,
      },
    ),
  );

  Future<List<Map<String, dynamic>>> _rpcRows(
    String function,
    Map<String, dynamic> params,
  ) async {
    final dynamic result = await _guard(
      () => _client.rpc<dynamic>(function, params: params),
    );
    if (result is! List) return const <Map<String, dynamic>>[];
    return result.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  /// Turns a Postgres error into a [StoryException].
  ///
  /// The triggers raise with `errcode = 'P0001'` and the rule name as the
  /// message, so the message *is* the code here. Anything else — a network
  /// failure, a 500 — becomes [StoryFailure.unknown]: the UI has one thing to
  /// say about all of them anyway.
  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (error) {
      throw StoryException(
        StoryFailure.fromCode(error.message.trim()),
        error.message,
      );
    } on AuthException catch (error) {
      throw StoryException(StoryFailure.notAuthenticated, error.message);
    }
  }
}
