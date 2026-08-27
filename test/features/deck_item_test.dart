/// Unit tests for the deck building logic.
///
/// The deck must never close on an ad card, because closing on an ad reads as a
/// paywall. The interleaving algorithm is tested for correctness with various
/// fact list lengths, including edge cases.
library;

import 'package:aja/features/facts/domain/deck_item.dart';
import 'package:aja/features/facts/domain/fact.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper to build a test fact with the given ID. All fields are filled with
/// dummy data but are consistent for easy inspection.
Fact _buildFact(String id) {
  return Fact(
    id: id,
    category: FactCategory.body,
    question: LocalizedText(es: 'Pregunta $id', en: 'Question $id'),
    answer: LocalizedText(es: 'Respuesta $id', en: 'Answer $id'),
    detail: LocalizedText(es: 'Detalle $id', en: 'Detail $id'),
    source: 'Source $id',
    sourceUrl: '',
  );
}

void main() {
  group('buildDeck', () {
    test('returns only fact items when withAds is false', () {
      final List<Fact> facts = [
        _buildFact('1'),
        _buildFact('2'),
        _buildFact('3'),
      ];

      final List<DeckItem> deck = buildDeck(facts, withAds: false);

      expect(deck, hasLength(3));
      expect(deck.every((DeckItem item) => item is FactItem), isTrue);
      expect(
        deck.map((DeckItem item) => (item as FactItem).fact.id),
        equals(['1', '2', '3']),
      );
    });

    test('inserts ad items at the correct intervals when withAds is true', () {
      // Create 20 facts. With adCardEveryNCards = 6, ads should appear after
      // facts 6, 12, and 18 (but NOT after fact 20, the last one).
      final List<Fact> facts = List<Fact>.generate(
        20,
        (int i) => _buildFact('$i'),
      );

      final List<DeckItem> deck = buildDeck(facts, withAds: true);

      // 20 facts + 3 ads = 23 items total
      expect(deck, hasLength(23));

      // Find the positions of ad items
      final List<int> adPositions = <int>[];
      for (int i = 0; i < deck.length; i++) {
        if (deck[i] is AdItem) {
          adPositions.add(i);
        }
      }

      // Ads should be at positions 6, 13, 20 (after every 6th fact)
      // Position 6: after facts 0-5 (6 items), then ad at position 6
      // Position 13: after facts 0-11 (12 items), then ad, plus fact 12-12 = 7, so 6+1+6 = 13
      // Position 20: after 18 facts + 2 ads = 20 items, then ad at position 20
      expect(adPositions, equals([6, 13, 20]));
    });

    test('never ends with an ad item', () {
      // Test with various lengths including a multiple of adCardEveryNCards
      final List<List<int>> testLengths = <List<int>>[
        [5], // Less than adCardEveryNCards
        [6], // Exactly adCardEveryNCards (edge case)
        [7], // Just over adCardEveryNCards
        [12], // Exactly 2x adCardEveryNCards (edge case)
        [13], // Just over 2x adCardEveryNCards
        [18], // Exactly 3x adCardEveryNCards (edge case)
        [20], // Common case
      ];

      for (final List<int> lengths in testLengths) {
        final int length = lengths.first;
        final List<Fact> facts = List<Fact>.generate(
          length,
          (int i) => _buildFact('$i'),
        );
        final List<DeckItem> deck = buildDeck(facts, withAds: true);

        expect(
          deck.isNotEmpty && deck.last is FactItem,
          isTrue,
          reason: 'Deck of length $length should not end with an ad',
        );
      }
    });

    test('produces unique keys for all items in the deck', () {
      final List<Fact> facts = List<Fact>.generate(
        15,
        (int i) => _buildFact('$i'),
      );
      final List<DeckItem> deck = buildDeck(facts, withAds: true);

      final Set<String> keys = <String>{};
      for (final DeckItem item in deck) {
        keys.add(item.key);
      }

      expect(
        keys.length,
        equals(deck.length),
        reason: 'All keys must be unique',
      );
    });

    test('returns an empty deck when facts list is empty', () {
      final List<DeckItem> deck = buildDeck(<Fact>[], withAds: true);
      expect(deck, isEmpty);
    });

    test('empty facts with withAds false also returns empty deck', () {
      final List<DeckItem> deck = buildDeck(<Fact>[], withAds: false);
      expect(deck, isEmpty);
    });
  });
}
