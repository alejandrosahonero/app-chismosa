import 'package:chismosa/features/stories/domain/story.dart';
import 'package:flutter/foundation.dart';

/// Everything that decides which cards the deck deals.
///
/// One value object rather than five arguments threaded through the providers:
/// the deck has to rebuild when *any* of these changes, and comparing one
/// object is how the controller knows a rebuild is needed without every screen
/// remembering to invalidate it.
@immutable
class FeedQuery {
  const FeedQuery({
    this.groupId,
    this.category,
    this.languages = const <String>[],
    this.countryCode,
    this.sort = StorySort.hot,
  });

  /// Group whose members' stories to show, or null for the worldwide deck.
  final String? groupId;

  /// null means every category. [StoryCategory.anything] as a *filter* also
  /// means every category — it is the catch-all bucket, so filtering by it
  /// would hide the stories that bothered to pick a shelf.
  final StoryCategory? category;

  /// Languages the reader accepts. Empty means "do not filter": a reader who
  /// somehow ends up with no languages must still get a deck.
  final List<String> languages;

  /// Restricts the deck to one country. Null is the point of the app — stories
  /// from everywhere — so this is opt-in.
  final String? countryCode;

  final StorySort sort;

  /// The `category` argument `feed()` expects. Both nulls collapse to the same
  /// "no filter" so the server does not have to know about the distinction.
  String? get categoryParam =>
      category == null || category == StoryCategory.anything
      ? null
      : category!.id;

  List<String>? get languagesParam => languages.isEmpty ? null : languages;

  FeedQuery copyWith({
    Object? groupId = _unset,
    Object? category = _unset,
    List<String>? languages,
    Object? countryCode = _unset,
    StorySort? sort,
  }) => FeedQuery(
    // Sentinel rather than null-coalescing: every one of these fields has null
    // as a meaningful value ("worldwide", "every category"), so `?? this.x`
    // would make clearing a filter impossible.
    groupId: groupId == _unset ? this.groupId : groupId as String?,
    category: category == _unset ? this.category : category as StoryCategory?,
    languages: languages ?? this.languages,
    countryCode: countryCode == _unset
        ? this.countryCode
        : countryCode as String?,
    sort: sort ?? this.sort,
  );

  static const Object _unset = Object();

  @override
  bool operator ==(Object other) =>
      other is FeedQuery &&
      other.groupId == groupId &&
      other.category == category &&
      other.countryCode == countryCode &&
      other.sort == sort &&
      listEquals(other.languages, languages);

  @override
  int get hashCode => Object.hash(
    groupId,
    category,
    countryCode,
    sort,
    Object.hashAll(languages),
  );

  @override
  String toString() =>
      'FeedQuery(group: $groupId, category: ${category?.id}, '
      'langs: $languages, country: $countryCode, sort: ${sort.id})';
}
