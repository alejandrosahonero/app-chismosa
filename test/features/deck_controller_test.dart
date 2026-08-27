/// Tests for the deck controller state management.
///
/// The controller owns the card stack position, reveal state, and progress
/// persistence. Tests verify that state mutations happen correctly, that
/// progress survives a container rebuild, and that edge cases like exhaustion
/// are handled safely.

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
/// This prevents the deck from inserting ad cards, so the tests do not depend
/// on the AdMob SDK being initialized.
class _FakePremiumController extends PremiumController {
  @override
  Future<PremiumStatus> build() async =>
      const PremiumStatus(isPremium: true, storeAvailable: false);
}

/// Fact ids in deck order, skipping any ad slots `buildDeck` interleaves.
List<String> _idsOf(List<DeckItem> items) =>
    items.whereType<FactItem>().map((FactItem item) => item.fact.id).toList();

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

void main() {
  group('DeckController', () {
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          premiumControllerProvider.overrideWith(_FakePremiumController.new),
          factsProvider.overrideWith(
            (Ref ref) async => [
              _buildFact('1'),
              _buildFact('2'),
              _buildFact('3'),
            ],
          ),
        ],
      );
    });

    tearDown(() => container.dispose());

    test(
      'initial state has index 0, nothing seen, revealed false, not exhausted',
      () async {
        await container.read(deckControllerProvider.future);
        final DeckState state = container
            .read(deckControllerProvider)
            .requireValue;

        expect(state.index, equals(0));
        expect(state.seenIds, isEmpty);
        expect(state.revealed, isFalse);
        expect(state.isExhausted, isFalse);
      },
    );

    test('toggleReveal flips revealed state', () async {
      await container.read(deckControllerProvider.future);
      final DeckController controller = container.read(
        deckControllerProvider.notifier,
      );

      DeckState state = container.read(deckControllerProvider).requireValue;
      expect(state.revealed, isFalse);

      controller.toggleReveal();
      state = container.read(deckControllerProvider).requireValue;
      expect(state.revealed, isTrue);

      controller.toggleReveal();
      state = container.read(deckControllerProvider).requireValue;
      expect(state.revealed, isFalse);
    });

    test(
      'next() advances index, records the id, and resets revealed',
      () async {
        await container.read(deckControllerProvider.future);
        final DeckController controller = container.read(
          deckControllerProvider.notifier,
        );

        // Reveal the card
        controller.toggleReveal();
        DeckState state = container.read(deckControllerProvider).requireValue;
        expect(state.revealed, isTrue);

        // Call next()
        final DeckItem? dismissed = await controller.next();
        state = container.read(deckControllerProvider).requireValue;

        expect(state.seenIds, equals(<String>{'1'}));
        expect(state.revealed, isFalse);
        expect(dismissed, isA<FactItem>());

        // The card just swiped is behind the user either way: still in `items`
        // with the index moved past it, or dropped from `items` entirely if the
        // deck rebuilt in between (premium settling does exactly that). Both
        // are correct, so the assertion is on what the user sees.
        expect((state.current! as FactItem).fact.id, equals('2'));
      },
    );

    test('next() returns the dismissed deck item', () async {
      await container.read(deckControllerProvider.future);
      final DeckState initialState = container
          .read(deckControllerProvider)
          .requireValue;
      final DeckItem initialCard = initialState.current!;
      final DeckController controller = container.read(
        deckControllerProvider.notifier,
      );

      final DeckItem? dismissed = await controller.next();

      expect(dismissed, equals(initialCard));
    });

    test(
      'calling next() until exhausted sets isExhausted true and returns null',
      () async {
        await container.read(deckControllerProvider.future);
        final DeckController controller = container.read(
          deckControllerProvider.notifier,
        );

        // Advance 3 times (3 facts total)
        await controller.next();
        await controller.next();
        await controller.next();

        final DeckState state = container
            .read(deckControllerProvider)
            .requireValue;
        expect(state.isExhausted, isTrue);

        // One more call should return null and not throw
        final DeckItem? result = await controller.next();
        expect(result, isNull);
      },
    );

    test('progress persists across container rebuilds', () async {
      // First container: advance by 2
      await container.read(deckControllerProvider.future);
      final DeckController controller = container.read(
        deckControllerProvider.notifier,
      );

      await controller.next();
      await controller.next();

      DeckState state = container.read(deckControllerProvider).requireValue;
      expect(state.seenIds, equals(<String>{'1', '2'}));

      // Get the SharedPreferences instance
      final SharedPreferences prefs = container.read(sharedPreferencesProvider);

      // Dispose old container
      container.dispose();

      // Create new container with the SAME SharedPreferences instance
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          premiumControllerProvider.overrideWith(_FakePremiumController.new),
          factsProvider.overrideWith(
            (Ref ref) async => [
              _buildFact('1'),
              _buildFact('2'),
              _buildFact('3'),
            ],
          ),
        ],
      );

      // The new deck holds only the card that was never swiped.
      await container.read(deckControllerProvider.future);
      state = container.read(deckControllerProvider).requireValue;
      expect(state.seenIds, equals(<String>{'1', '2'}));
      expect(_idsOf(state.items), equals(<String>['3']));
      expect(state.index, equals(0));
    });

    test('restart() deals every card of the filter again', () async {
      await container.read(deckControllerProvider.future);
      final DeckController controller = container.read(
        deckControllerProvider.notifier,
      );

      // Advance and verify
      await controller.next();
      await controller.next();
      DeckState state = container.read(deckControllerProvider).requireValue;
      expect(state.seenIds, equals(<String>{'1', '2'}));

      // Restart
      await controller.restart();
      state = container.read(deckControllerProvider).requireValue;

      expect(state.index, equals(0));
      expect(state.seenIds, isEmpty);
      expect(_idsOf(state.items).toSet(), equals(<String>{'1', '2', '3'}));
      expect(state.revealed, isFalse);
    });
  });

  /// The category chips are four views of one catalogue, not four decks. What
  /// the user read under one chip has to stay read under every other one —
  /// finishing "Ciencia" and switching to "Todas" used to deal those same cards
  /// straight back, because progress was a counter per filter and a count only
  /// means something against one fixed ordering.
  group('DeckController progress across category filters', () {
    late ProviderContainer container;

    final List<Fact> facts = <Fact>[
      _buildFact('sci-1', category: FactCategory.science),
      _buildFact('sci-2', category: FactCategory.science),
      _buildFact('body-1'),
      _buildFact('body-2'),
    ];

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          premiumControllerProvider.overrideWith(_FakePremiumController.new),
          factsProvider.overrideWith((Ref ref) async => facts),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('a category read to the end does not come back unfiltered', () async {
      container
          .read(categoryFilterProvider.notifier)
          .select(FactCategory.science);
      DeckState state = await container.read(deckControllerProvider.future);
      final DeckController controller = container.read(
        deckControllerProvider.notifier,
      );

      while (!state.isExhausted) {
        await controller.next();
        state = container.read(deckControllerProvider).requireValue;
      }

      container.read(categoryFilterProvider.notifier).select(null);
      final DeckState all = await container.read(deckControllerProvider.future);

      expect(_idsOf(all.items), equals(<String>['body-1', 'body-2']));
    });

    test('reading under "all" also counts under the category chip', () async {
      await container.read(deckControllerProvider.future);
      final DeckController controller = container.read(
        deckControllerProvider.notifier,
      );

      // 'sci-1' is the first card of the unfiltered deck.
      await controller.next();

      container
          .read(categoryFilterProvider.notifier)
          .select(FactCategory.science);
      final DeckState science = await container.read(
        deckControllerProvider.future,
      );

      expect(_idsOf(science.items), equals(<String>['sci-2']));
    });

    test('restart under a chip leaves the other categories read', () async {
      container
          .read(categoryFilterProvider.notifier)
          .select(FactCategory.science);
      DeckState state = await container.read(deckControllerProvider.future);
      final DeckController controller = container.read(
        deckControllerProvider.notifier,
      );

      while (!state.isExhausted) {
        await controller.next();
        state = container.read(deckControllerProvider).requireValue;
      }
      await controller.restart();

      // Science is dealable again; body was never touched either way.
      expect(
        container.read(deckControllerProvider).requireValue.seenIds,
        isEmpty,
      );

      // Now read a body card under "all", then restart science again: the body
      // card must stay read.
      container.read(categoryFilterProvider.notifier).select(FactCategory.body);
      await container.read(deckControllerProvider.future);
      await container.read(deckControllerProvider.notifier).next();

      container
          .read(categoryFilterProvider.notifier)
          .select(FactCategory.science);
      await container.read(deckControllerProvider.future);
      await container.read(deckControllerProvider.notifier).restart();

      expect(
        container.read(deckControllerProvider).requireValue.seenIds,
        equals(<String>{'body-1'}),
      );
    });
  });
}
