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
    this.chapter = 1,
    this.parentId,
    this.nextId,
    this.isHouse = false,
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
    chapter: (row['chapter'] as num?)?.toInt() ?? 1,
    parentId: row['parent_id'] as String?,
    nextId: row['next_id'] as String?,
    isHouse: (row['is_house'] as bool?) ?? false,
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

  /// Which part of a saga this is. 1 for a story that stands on its own.
  final int chapter;

  /// The previous part, when this one continues it.
  final String? parentId;

  /// The next part, when the author has written one. Only `story_detail()`
  /// knows it; the deck leaves it null.
  final String? nextId;

  /// Written by the Chismosa team, and labelled as such on the card. Never
  /// passed off as a user's: an app that sells authenticity cannot be caught
  /// inventing it.
  final bool isHouse;

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
    chapter: chapter,
    parentId: parentId,
    nextId: nextId,
    isHouse: isHouse,
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

/// Where the reader stands against today's publishing quota.
@immutable
class PublishStatus {
  const PublishStatus({
    required this.postedToday,
    required this.dailyLimit,
    required this.credits,
    required this.isPremium,
  });

  factory PublishStatus.fromRow(Map<String, dynamic> row) => PublishStatus(
    postedToday: (row['posted_today'] as num?)?.toInt() ?? 0,
    dailyLimit: (row['daily_limit'] as num?)?.toInt() ?? 1,
    credits: (row['credits'] as num?)?.toInt() ?? 0,
    isPremium: (row['is_premium'] as bool?) ?? false,
  );

  final int postedToday;
  final int dailyLimit;

  /// Extra stories bought with rewarded videos, not yet spent.
  final int credits;

  final bool isPremium;

  /// Stories this reader can still publish today, or null for "no limit".
  int? get remaining => isPremium
      ? null
      : (dailyLimit - postedToday).clamp(0, dailyLimit) + credits;

  bool get canPublish => remaining == null || remaining! > 0;
}

/// One of the reader's own stories, with how it is doing.
@immutable
class OwnStory {
  const OwnStory({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.likesCount,
    required this.messagesCount,
    required this.hidden,
    required this.chapter,
    required this.hasNext,
    this.groupId,
    this.underReview = false,
  });

  factory OwnStory.fromRow(Map<String, dynamic> row) => OwnStory(
    id: row['id']! as String,
    body: (row['body'] as String?) ?? '',
    createdAt:
        DateTime.tryParse((row['created_at'] as String?) ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
    likesCount: (row['likes_count'] as num?)?.toInt() ?? 0,
    messagesCount: (row['messages_count'] as num?)?.toInt() ?? 0,
    hidden: (row['hidden'] as bool?) ?? false,
    chapter: (row['chapter'] as num?)?.toInt() ?? 1,
    hasNext: (row['has_next'] as bool?) ?? false,
    groupId: row['group_id'] as String?,
    underReview: row['review_status'] == 'pending',
  );

  final String id;
  final String body;
  final DateTime createdAt;
  final int likesCount;
  final int messagesCount;

  /// Hidden by reports. Still listed: an author whose story vanished without a
  /// word would assume the app is broken.
  final bool hidden;

  final int chapter;

  /// A story can be continued once. After that the saga goes on from the
  /// newest part.
  final bool hasNext;

  /// The group it was posted in, so its continuation lands in the same place.
  final String? groupId;

  /// Hidden by a "names someone" report and waiting for a person to look at
  /// it. Said differently on screen from a story hidden by the report count:
  /// this one may well come back.
  final bool underReview;

  bool get canContinue => !hidden && !hasNext && chapter < 20;
}
