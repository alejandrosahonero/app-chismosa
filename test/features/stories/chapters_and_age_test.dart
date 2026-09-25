/// Chapters, the author's own stories, and the card's "how long ago".
library;

import 'package:chismosa/features/stories/data/story_repository.dart';
import 'package:chismosa/features/stories/domain/story.dart';
import 'package:chismosa/features/stories/presentation/widgets/story_card_view.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a feed row carries its chapter and the part it continues', () {
    final Story story = Story.fromRow(const <String, dynamic>{
      'id': 's2',
      'body': 'La segunda parte de algo que empezó ayer.',
      'category': 'familia',
      'lang': 'es',
      'created_at': '2026-09-01T10:00:00Z',
      'chapter': 2,
      'parent_id': 's1',
    });
    expect(story.chapter, 2);
    expect(story.parentId, 's1');
    expect(story.withLike(liked: true).chapter, 2);
  });

  test('an old row without chapters reads as a standalone story', () {
    final Story story = Story.fromRow(const <String, dynamic>{
      'id': 's',
      'body': 'Una historia de antes de los capítulos.',
    });
    expect(story.chapter, 1);
    expect(story.parentId, isNull);
  });

  test('only a visible story without a next part can be continued', () {
    OwnStory own({
      bool hidden = false,
      bool hasNext = false,
      int chapter = 1,
    }) => OwnStory(
      id: 'x',
      body: 'b',
      createdAt: DateTime.utc(2026),
      likesCount: 0,
      messagesCount: 0,
      hidden: hidden,
      chapter: chapter,
      hasNext: hasNext,
    );
    expect(own().canContinue, isTrue);
    expect(own(hidden: true).canContinue, isFalse);
    expect(own(hasNext: true).canContinue, isFalse);
    expect(own(chapter: 20).canContinue, isFalse);
  });

  test('the server refusals for personal data and chapters are named', () {
    expect(StoryFailure.fromCode('personal_data'), StoryFailure.personalData);
    expect(
      StoryFailure.fromCode('already_continued'),
      StoryFailure.cannotContinue,
    );
  });

  test('age is said in the fewest characters', () async {
    final AppLocalizations l10n = await AppLocalizations.delegate.load(
      const Locale('es'),
    );
    final DateTime now = DateTime.utc(2026, 9, 25, 12);
    expect(
      storyAge(l10n, now.subtract(const Duration(seconds: 20)), now),
      'ahora',
    );
    expect(
      storyAge(l10n, now.subtract(const Duration(minutes: 12)), now),
      '12 min',
    );
    expect(storyAge(l10n, now.subtract(const Duration(hours: 3)), now), '3 h');
    expect(storyAge(l10n, now.subtract(const Duration(days: 5)), now), '5 d');
  });
}
