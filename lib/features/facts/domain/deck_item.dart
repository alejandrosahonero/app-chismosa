import 'package:aja/core/config/app_config.dart';
import 'package:aja/features/facts/domain/fact.dart';
import 'package:flutter/foundation.dart';

/// Something the deck can render as a card.
///
/// Sealed so the widget layer has to handle both cases: an ad slot is a first
/// class member of the deck, not a special case bolted onto the fact card.
@immutable
sealed class DeckItem {
  const DeckItem();

  /// Unique within a deck, used as the widget key so the stack does not reuse
  /// the wrong element's state while cards animate out.
  String get key;
}

/// A question/answer card.
@immutable
class FactItem extends DeckItem {
  const FactItem(this.fact);

  final Fact fact;

  @override
  String get key => 'fact:${fact.id}';
}

/// An ad slot mimicking a card, swiped exactly like the rest of the deck.
@immutable
class AdItem extends DeckItem {
  const AdItem(this.slot);

  /// Position of this slot in the deck. Part of [key] so two ad cards never
  /// share widget state — otherwise the second one would try to reuse the first
  /// one's already-disposed `BannerAd`.
  final int slot;

  @override
  String get key => 'ad:$slot';
}

/// Interleaves ad cards into a list of facts.
///
/// Returns the facts untouched when [withAds] is false (premium user, no
/// consent, or ads not initialized yet), so the deck never reserves a slot it
/// cannot fill.
List<DeckItem> buildDeck(List<Fact> facts, {required bool withAds}) {
  if (!withAds) {
    return facts.map<DeckItem>(FactItem.new).toList(growable: false);
  }

  final List<DeckItem> items = <DeckItem>[];
  int slot = 0;

  for (int i = 0; i < facts.length; i++) {
    items.add(FactItem(facts[i]));

    // Never right at the end: closing the deck on an ad reads as a paywall.
    final bool isLast = i == facts.length - 1;
    if (!isLast && (i + 1) % AppConfig.adCardEveryNCards == 0) {
      items.add(AdItem(slot++));
    }
  }

  return List<DeckItem>.unmodifiable(items);
}
