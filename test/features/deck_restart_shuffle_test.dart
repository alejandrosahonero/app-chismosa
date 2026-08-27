/// Tests for the shuffle-and-persist behaviour of [DeckController.restart].
///
/// The first pass through a category must keep the curated file order,
/// [restart] must reorder the deck (not merely rewind it), and the new order
/// must survive a rebuild — otherwise buying premium mid-deck would reshuffle
/// the cards under the user.

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

/// Enough facts that a shuffle landing on the identical order is vanishingly
/// unlikely (1 in 30! if it ever happened).
final List<Fact> _facts = List<Fact>.generate(30, (int i) => _buildFact('$i'));

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

void main() {
  group('DeckController restart shuffle', () {
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

    test(
      'the first run through a category keeps the curated file order',
      () async {
        final DeckState state = await container.read(
          deckControllerProvider.future,
        );

        expect(
          _idsOf(state.items),
          equals(_facts.map((Fact fact) => fact.id).toList()),
        );
      },
    );

    test('restart deals the same cards in a different order', () async {
      final DeckState before = await container.read(
        deckControllerProvider.future,
      );
      final List<String> originalOrder = _idsOf(before.items);

      final DeckController controller = container.read(
        deckControllerProvider.notifier,
      );
      await controller.restart();

      final DeckState after = container
          .read(deckControllerProvider)
          .requireValue;
      final List<String> shuffledOrder = _idsOf(after.items);

      expect(shuffledOrder.toSet(), equals(originalOrder.toSet()));
      expect(shuffledOrder, isNot(equals(originalOrder)));
    });

    test('restart sends the user back to the first card', () async {
      await container.read(deckControllerProvider.future);
      final DeckController controller = container.read(
        deckControllerProvider.notifier,
      );

      // Advance a couple of cards before restarting.
      await controller.next();
      await controller.next();

      await controller.restart();
      final DeckState state = container
          .read(deckControllerProvider)
          .requireValue;

      expect(state.index, equals(0));
      expect(state.seenIds, isEmpty);
    });

    test('the shuffled order survives a rebuild', () async {
      await container.read(deckControllerProvider.future);
      final DeckController controller = container.read(
        deckControllerProvider.notifier,
      );
      await controller.restart();

      final List<String> shuffledOrder = _idsOf(
        container.read(deckControllerProvider).requireValue.items,
      );

      // Force the controller to rebuild from scratch, as buying premium
      // mid-deck would do.
      container.invalidate(deckControllerProvider);
      final DeckState rebuilt = await container.read(
        deckControllerProvider.future,
      );

      expect(_idsOf(rebuilt.items), equals(shuffledOrder));
    });
  });
}
