import 'package:chismosa/core/config/app_config.dart';
import 'package:chismosa/core/widgets/deck/deck_card.dart';
import 'package:chismosa/features/stories/domain/story.dart';
import 'package:flutter/foundation.dart';

/// One card of the stories deck.
///
/// Sealed so the widget layer is forced to handle both cases: the ad slot is a
/// full member of the deck, swiped exactly like a story, not a special case
/// bolted onto the story card.
@immutable
sealed class StoryDeckItem implements DeckCard {
  const StoryDeckItem();
}

/// Somebody's story.
@immutable
class StoryCard extends StoryDeckItem {
  const StoryCard(this.story);

  final Story story;

  @override
  String get key => 'story:${story.id}';
}

/// An ad slot wearing the same shell as a story.
@immutable
class StoryAdCard extends StoryDeckItem {
  const StoryAdCard(this.slot);

  /// Position of this slot in the deck, part of the key so two ad cards never
  /// share widget state.
  final int slot;

  @override
  String get key => 'ad:$slot';
}

/// Interleaves ad slots into a page of stories.
///
/// Same two rules as the deck this app grew out of, and for the same reasons:
/// one slot every [AppConfig.adCardEveryNCards] cards — never fewer than five —
/// and **never one at the very end**, because closing a session on an advert
/// reads as a paywall.
///
/// [startSlot] carries the numbering across pages: the deck appends a fresh
/// page to cards the user has not reached yet, and restarting the count would
/// hand the new slots the keys of slots still on screen.
List<StoryDeckItem> buildStoryDeck(
  List<Story> stories, {
  required bool withAds,
  int startSlot = 0,
}) {
  if (!withAds) {
    return stories.map<StoryDeckItem>(StoryCard.new).toList(growable: false);
  }

  final List<StoryDeckItem> items = <StoryDeckItem>[];
  int slot = startSlot;

  for (int i = 0; i < stories.length; i++) {
    items.add(StoryCard(stories[i]));

    final bool isLast = i == stories.length - 1;
    if (!isLast && (i + 1) % AppConfig.adCardEveryNCards == 0) {
      items.add(StoryAdCard(slot++));
    }
  }

  return List<StoryDeckItem>.unmodifiable(items);
}

/// Number of ad slots [buildStoryDeck] would consume for [count] stories.
///
/// Lets the caller advance [buildStoryDeck.startSlot] without walking the list
/// it just built.
int adSlotsFor(int count) =>
    count <= 0 ? 0 : (count - 1) ~/ AppConfig.adCardEveryNCards;
