import 'package:flutter/foundation.dart';

/// Buckets a story can be filed under.
///
/// Deliberately generic, plus a catch-all. A taxonomy nobody fits into just
/// pushes every card into "other", and a writer who has to pick a shelf before
/// telling the story is a writer who closes the sheet.
///
/// The ids are the strings the `stories.category` check constraint accepts; a
/// value that is not in this enum cannot be published, and one that arrives
/// from the server is treated as [anything] rather than throwing — unlike the
/// inherited catalogue, this content is written by strangers and a single bad
/// row must not take the deck down.
enum StoryCategory {
  anything('cualquiera'),
  love('amor'),
  family('familia'),
  work('trabajo'),
  friendship('amistad'),
  school('escuela'),
  neighbours('vecinos'),
  money('dinero');

  const StoryCategory(this.id);

  /// Value stored in the database.
  final String id;

  /// Categories offered as a filter, in the order the chips show them.
  ///
  /// [anything] leads because it is both a real bucket and the honest answer
  /// for most stories.
  static const List<StoryCategory> filters = StoryCategory.values;

  static StoryCategory fromId(String? id) {
    for (final StoryCategory category in StoryCategory.values) {
      if (category.id == id) return category;
    }
    return StoryCategory.anything;
  }
}

/// How the deck orders what it deals.
enum StorySort {
  /// Likes decayed by age, so a card that is doing well right now beats one
  /// that did well last month. Computed server side; see `feed()`.
  hot('hot'),

  /// Straight reverse chronological. The only way a story published a minute
  /// ago is ever seen by anyone.
  newest('new');

  const StorySort(this.id);

  final String id;
}

/// One card of the deck: somebody's short anonymous story.
///
/// There is no author field, on purpose and permanently. The server never sends
/// one — see the comment above `feed()` in `0002_logic.sql` — because in a group
/// of six friends a story plus an account id is a name.
@immutable
class Story {
  const Story({
    required this.id,
    required this.body,
    required this.category,
    required this.lang,
    required this.createdAt,
    required this.likesCount,
    required this.messagesCount,
    this.countryCode,
    this.closedAt,
    this.liked = false,
    this.joined = false,
  });

  /// Parses one row of `feed()` or `story_detail()`.
  ///
  /// Tolerant by design: a column the server adds later, or a category this
  /// build does not know about, must not break a deck that is already
  /// installed on somebody's phone.
  factory Story.fromRow(Map<String, dynamic> row) => Story(
    id: row['id']! as String,
    body: row['body']! as String,
    category: StoryCategory.fromId(row['category'] as String?),
    lang: (row['lang'] as String?) ?? 'es',
    createdAt:
        DateTime.tryParse((row['created_at'] as String?) ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
    likesCount: (row['likes_count'] as num?)?.toInt() ?? 0,
    messagesCount: (row['messages_count'] as num?)?.toInt() ?? 0,
    countryCode: row['country_code'] as String?,
    closedAt: DateTime.tryParse((row['closed_at'] as String?) ?? '')?.toUtc(),
    liked: (row['liked'] as bool?) ?? false,
    joined: (row['joined'] as bool?) ?? false,
  );

  final String id;

  /// The story itself, 20 to 600 characters. The only content there is.
  final String body;

  final StoryCategory category;

  /// Two letter language of the body, so the deck can leave out languages the
  /// reader does not speak.
  final String lang;

  /// Two letter country, or null when the device never reported one. Country
  /// and nothing finer: a city plus an anonymous story is a doxxing kit.
  final String? countryCode;

  final DateTime createdAt;
  final int likesCount;
  final int messagesCount;

  /// Set once the thread has been quiet long enough to be closed. The card is
  /// still readable; it just no longer takes messages.
  final DateTime? closedAt;

  /// Whether *this* reader already liked it. Part of the row rather than a
  /// separate query so a card never renders with the wrong heart for a frame.
  final bool liked;

  /// Whether this reader is already in the thread.
  final bool joined;

  bool get isClosed => closedAt != null;

  /// Optimistic local echo of a like, so the card reacts to the swipe on the
  /// frame it happens instead of when the round trip lands.
  Story withLike({required bool liked}) {
    if (liked == this.liked) return this;
    return copyWith(
      liked: liked,
      likesCount: (likesCount + (liked ? 1 : -1)).clamp(0, 1 << 30),
    );
  }

  Story copyWith({
    int? likesCount,
    int? messagesCount,
    bool? liked,
    bool? joined,
    DateTime? closedAt,
  }) => Story(
    id: id,
    body: body,
    category: category,
    lang: lang,
    createdAt: createdAt,
    likesCount: likesCount ?? this.likesCount,
    messagesCount: messagesCount ?? this.messagesCount,
    countryCode: countryCode,
    closedAt: closedAt ?? this.closedAt,
    liked: liked ?? this.liked,
    joined: joined ?? this.joined,
  );

  @override
  bool operator ==(Object other) =>
      other is Story &&
      other.id == id &&
      other.liked == liked &&
      other.joined == joined &&
      other.likesCount == likesCount &&
      other.messagesCount == messagesCount;

  @override
  int get hashCode => Object.hash(id, liked, joined, likesCount, messagesCount);
}
