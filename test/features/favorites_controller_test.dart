/// Tests for the favorites controller state management.
///
/// The controller owns the set of saved fact IDs, resolves them against the
/// catalogue, and persists changes to shared preferences. Tests verify that
/// toggling works correctly, that resolved lists drop stale IDs without
/// crashing, that ordering is newest-first, and that state survives a
/// container rebuild.

library;

import 'package:aja/features/facts/domain/fact.dart';
import 'package:aja/features/facts/presentation/providers/facts_providers.dart';
import 'package:aja/features/facts/presentation/providers/favorites_controller.dart';
import 'package:aja/services/billing/premium_controller.dart';
import 'package:aja/services/billing/premium_state.dart';
import 'package:aja/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake premium controller that always returns isPremium: true.
///
/// This keeps all tests focused on favorites logic, not premium gating.
class _FakePremiumController extends PremiumController {
  @override
  Future<PremiumStatus> build() async =>
      const PremiumStatus(isPremium: true, storeAvailable: false);
}

/// Helper to build a test fact with the given ID.
Fact _fact(String id) {
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
  group('FavoritesController', () {
    late ProviderContainer container;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          premiumControllerProvider.overrideWith(_FakePremiumController.new),
          factsProvider.overrideWith(
            (Ref ref) async => [_fact('1'), _fact('2'), _fact('3')],
          ),
        ],
      );
    });

    tearDown(() => container.dispose());

    test('favoritesProvider starts empty', () async {
      final Set<String> state = container.read(favoritesProvider);
      expect(state, isEmpty);
    });

    test('toggle() returns true when adding and state contains id', () async {
      final FavoritesController controller = container.read(
        favoritesProvider.notifier,
      );

      final bool added = await controller.toggle('a');

      expect(added, isTrue);
      expect(container.read(favoritesProvider), contains('a'));
    });

    test(
      'toggle() returns false when removing and state no longer contains id',
      () async {
        final FavoritesController controller = container.read(
          favoritesProvider.notifier,
        );

        // Add it first
        await controller.toggle('a');
        expect(container.read(favoritesProvider), contains('a'));

        // Remove it
        final bool added = await controller.toggle('a');

        expect(added, isFalse);
        expect(container.read(favoritesProvider), isNot(contains('a')));
      },
    );

    test('multiple toggles keep all ids', () async {
      final FavoritesController controller = container.read(
        favoritesProvider.notifier,
      );

      await controller.toggle('a');
      await controller.toggle('b');
      await controller.toggle('c');

      final Set<String> state = container.read(favoritesProvider);
      expect(state, containsAll(<String>['a', 'b', 'c']));
      expect(state.length, equals(3));
    });

    test('state persists across container rebuilds', () async {
      final FavoritesController controller = container.read(
        favoritesProvider.notifier,
      );

      // Toggle two ids in first container
      await controller.toggle('1');
      await controller.toggle('2');

      Set<String> state = container.read(favoritesProvider);
      expect(state, containsAll(<String>['1', '2']));

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
            (Ref ref) async => [_fact('1'), _fact('2'), _fact('3')],
          ),
        ],
      );

      // New container should still have both ids
      state = container.read(favoritesProvider);
      expect(state, containsAll(<String>['1', '2']));
    });

    test('favoriteFactsProvider returns facts newest first', () async {
      final FavoritesController controller = container.read(
        favoritesProvider.notifier,
      );

      // Save in order 1, 2, 3
      await controller.toggle('1');
      await controller.toggle('2');
      await controller.toggle('3');

      // Should come back in reverse order
      final List<Fact> facts = await container.read(
        favoriteFactsProvider.future,
      );

      expect(facts.length, equals(3));
      expect(facts[0].id, equals('3'));
      expect(facts[1].id, equals('2'));
      expect(facts[2].id, equals('1'));
    });

    test('favoriteFactsProvider silently drops non-existent ids', () async {
      final FavoritesController controller = container.read(
        favoritesProvider.notifier,
      );

      // Toggle a real id and a non-existent one
      await controller.toggle('2');
      await controller.toggle('does-not-exist');

      // Only the real fact should come back
      final List<Fact> facts = await container.read(
        favoriteFactsProvider.future,
      );

      expect(facts.length, equals(1));
      expect(facts[0].id, equals('2'));
    });

    test(
      'favoriteFactsProvider returns empty list when nothing is saved',
      () async {
        final List<Fact> facts = await container.read(
          favoriteFactsProvider.future,
        );

        expect(facts, isEmpty);
      },
    );
  });
}
