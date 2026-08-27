/// Tests for [DeckController]'s handling of [pinnedFactProvider].
///
/// A daily "question of the day" notification opens the app on one exact
/// card. Jumping the deck index straight to it would silently skip every
/// card between the current position and that one, so `_hoist` lifts the
/// pinned card out of the deck and drops it at the reading position instead,
/// closing ranks behind it. These tests pin down that nothing gets skipped,
/// duplicated, or lost in the process, including the edge cases called out
/// in `_hoist`'s own doc comment: a card the user already read, and a deck
/// that has already been exhausted.

library;

import 'package:aja/features/facts/domain/deck_item.dart';
import 'package:aja/features/facts/domain/fact.dart';
import 'package:aja/features/facts/presentation/providers/deck_controller.dart';
import 'package:aja/features/facts/presentation/providers/facts_providers.dart';
import 'package:aja/services/billing/premium_controller.dart';
import 'package:aja/services/billing/premium_state.dart';
import 'package:aja/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake premium controller that always returns isPremium: true.
///
/// Keeps the deck free of ad slots, so `items` maps 1:1 to facts and the id
/// order can be compared directly against the source list.
class _FakePremiumController extends PremiumController {
  @override
  Future<PremiumStatus> build() async =>
      const PremiumStatus(isPremium: true, storeAvailable: false);
}

/// Helper to build a test fact with the given ID.
Fact _buildFact(String id, {FactCategory category = FactCategory.body}) {
  return Fact(
    id: id,
    category: category,
    question: LocalizedText(es: 'Pregunta $id', en: 'Question $id'),
    answer: LocalizedText(es: 'Respuesta $id', en: 'Answer $id'),
    detail: LocalizedText(es: 'Detalle $id', en: 'Detail $id'),
    source: 'Source $id',
    sourceUrl: '',
  );
}

/// Twenty predictable ids ('0'..'19') so ordering assertions read like a
/// timeline instead of a hash.
final List<Fact> _bodyFacts = List<Fact>.generate(
  20,
  (int i) => _buildFact('$i'),
);

/// A single fact in a different category, used to prove that a pin filtered
/// out by the category chips is a no-op rather than a crash.
final Fact _scienceFact = _buildFact('sci-0', category: FactCategory.science);

final List<Fact> _facts = <Fact>[..._bodyFacts, _scienceFact];

/// Fact ids in deck order, skipping the ad slots `buildDeck` interleaves.
///
/// The deck is a mixed `List<DeckItem>` (see `buildDeck`): an `AdItem` can
/// land between fact cards even for a premium user, transiently, while
/// [isPremiumProvider] is still settling from its "not premium while
/// loading" default. Filtering keeps this helper correct for either case
/// without changing what any assertion checks — the fact ids stay in the
/// same relative order regardless of where an ad slot lands.
List<String> _idsOf(List<DeckItem> items) =>
    items.whereType<FactItem>().map((FactItem item) => item.fact.id).toList();

/// Every id in the catalogue minus the ones already swiped away.
///
/// The deck holds only unread cards, so this is what a rebuilt deck is expected
/// to contain — plus whatever a pin lifts back out of the read pile.
Set<String> _unreadIds(Set<String> read) =>
    _facts.map((Fact fact) => fact.id).toSet().difference(read);

void main() {
  group('DeckController pinned fact', () {
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          premiumControllerProvider.overrideWith(_FakePremiumController.new),
          factsProvider.overrideWith((Ref ref) async => _facts),
        ],
      );
    });

    tearDown(() => container.dispose());

    /// A reminder for a card further down the deck must not steal any of the
    /// cards on the way to it — they still come up, one place later.
    test(
      'pinning an upcoming card brings it forward without skipping anything',
      () async {
        await container.read(deckControllerProvider.future);
        final DeckController controller = container.read(
          deckControllerProvider.notifier,
        );

        // Advance past the first three cards, landing on '3'.
        await controller.next();
        await controller.next();
        await controller.next();

        container.read(pinnedFactProvider.notifier).pin('8');
        final DeckState after = await container.read(
          deckControllerProvider.future,
        );
        final List<String> idsAfter = _idsOf(after.items);

        expect(idsAfter[after.index], equals('8'));

        // '3'..'7' sat between the reading position and the pinned card;
        // they must still be ahead, in their original order.
        expect(
          idsAfter.sublist(after.index + 1, after.index + 6),
          equals(<String>['3', '4', '5', '6', '7']),
        );

        // Everything still unread is still in the deck, exactly once.
        expect(idsAfter.toSet(), equals(_unreadIds(<String>{'0', '1', '2'})));
        expect(idsAfter.length, equals(idsAfter.toSet().length));
      },
    );

    /// The case `_hoist`'s doc comment covers: the pinned card is not in the
    /// unread pile at all, so it has to be fetched out of the read pile and put
    /// back on top — without displacing the card that was about to come up.
    test('pinning a card the user already read puts it back on top', () async {
      await container.read(deckControllerProvider.future);
      final DeckController controller = container.read(
        deckControllerProvider.notifier,
      );

      // Advance to '5', leaving '0'..'4' already seen.
      for (int i = 0; i < 5; i++) {
        await controller.next();
      }

      final DeckState before = container
          .read(deckControllerProvider)
          .requireValue;
      final String upcomingId = _idsOf(before.items)[before.index];

      container.read(pinnedFactProvider.notifier).pin('2');
      final DeckState after = await container.read(
        deckControllerProvider.future,
      );
      final List<String> idsAfter = _idsOf(after.items);

      expect(idsAfter[after.index], equals('2'));
      // The card that was about to come up next must still be next, right
      // behind the pinned one — reviving a read card must not swallow it.
      expect(idsAfter[after.index + 1], equals(upcomingId));

      // The unread pile, plus the one card the pin brought back.
      expect(
        idsAfter.toSet(),
        equals(_unreadIds(<String>{'0', '1', '2', '3', '4'})..add('2')),
      );
      expect(idsAfter.length, equals(idsAfter.toSet().length));
    });

    /// A reminder tapped by somebody who already read everything has to work
    /// too: the pinned card lands on top and the deck finishes again right
    /// after it.
    test('pinning works on a deck that was already finished', () async {
      DeckState state = await container.read(deckControllerProvider.future);
      final DeckController controller = container.read(
        deckControllerProvider.notifier,
      );

      while (!state.isExhausted) {
        await controller.next();
        state = container.read(deckControllerProvider).requireValue;
      }
      expect(state.isExhausted, isTrue);

      container.read(pinnedFactProvider.notifier).pin('5');
      final DeckState afterPin = await container.read(
        deckControllerProvider.future,
      );

      expect(afterPin.isExhausted, isFalse);
      expect(_idsOf(afterPin.items)[afterPin.index], equals('5'));

      await controller.next();
      final DeckState finalState = container
          .read(deckControllerProvider)
          .requireValue;
      expect(finalState.isExhausted, isTrue);
    });

    /// A stale or malformed id (a notification tapped after the catalogue
    /// changed underneath it) must leave the deck exactly as it was, rather
    /// than guessing what the user meant.
    test('an unknown id leaves the deck untouched', () async {
      await container.read(deckControllerProvider.future);
      final DeckController controller = container.read(
        deckControllerProvider.notifier,
      );
      await controller.next();
      await controller.next();

      // Compared against a rebuild rather than the in-memory state: a rebuild
      // is exactly what pinning triggers, so this isolates the pin from the
      // deck simply being redealt without the two swiped cards.
      container.invalidate(deckControllerProvider);
      final DeckState before = await container.read(
        deckControllerProvider.future,
      );
      final List<String> idsBefore = _idsOf(before.items);

      container.read(pinnedFactProvider.notifier).pin('does-not-exist');
      final DeckState after = await container.read(
        deckControllerProvider.future,
      );

      expect(_idsOf(after.items), equals(idsBefore));
      expect(after.index, equals(before.index));
    });

    /// A pin for a card the category chips currently hide is not on the
    /// filtered deck at all, so it must be a no-op instead of emptying the
    /// deck or crashing the lookup.
    test(
      'a pinned fact filtered out by the category chips is ignored',
      () async {
        container
            .read(categoryFilterProvider.notifier)
            .select(FactCategory.body);
        final DeckState before = await container.read(
          deckControllerProvider.future,
        );
        final List<String> idsBefore = _idsOf(before.items);
        final int indexBefore = before.index;

        container.read(pinnedFactProvider.notifier).pin('sci-0');
        final DeckState after = await container.read(
          deckControllerProvider.future,
        );

        expect(_idsOf(after.items), equals(idsBefore));
        expect(after.index, equals(indexBefore));
      },
    );

    /// Duplicate ids would collide on `DeckItem.key` and corrupt the card
    /// stack's widget state, so whatever gets pinned, the deck must hold
    /// exactly the same set of ids it started with.
    test('the id set never changes, whatever is pinned', () async {
      await container.read(deckControllerProvider.future);
      final DeckController controller = container.read(
        deckControllerProvider.notifier,
      );
      await controller.next();
      await controller.next();

      const Set<String> read = <String>{'0', '1'};

      for (final String id in <String>['5', '0', '19', '2', '8']) {
        container.read(pinnedFactProvider.notifier).pin(id);
        final DeckState state = await container.read(
          deckControllerProvider.future,
        );
        final List<String> ids = _idsOf(state.items);

        // Always the unread pile, plus the pinned card whether or not it had
        // already been read. Never the same id twice.
        expect(ids.toSet(), equals(_unreadIds(read)..add(id)));
        expect(ids.length, equals(ids.toSet().length));
      }
    });
  });
}
