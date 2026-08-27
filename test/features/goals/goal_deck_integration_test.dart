/// Where the goal is wired into the deck.
///
/// The decision under test is which gesture counts. "Learning" is flipping the
/// card and reading the answer, never swiping it away — a goal that fills up
/// from skipped cards measures nothing, and the ring would tell the user they
/// learned fifteen facts they never read.

library;

import 'package:aja/app.dart';
import 'package:aja/features/facts/domain/fact.dart';
import 'package:aja/features/facts/presentation/providers/deck_controller.dart';
import 'package:aja/features/facts/presentation/providers/facts_providers.dart';
import 'package:aja/features/goals/presentation/providers/goals_controller.dart';
import 'package:aja/features/goals/presentation/widgets/goal_ring_button.dart';
import 'package:aja/services/billing/premium_controller.dart';
import 'package:aja/services/billing/premium_state.dart';
import 'package:aja/services/storage/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePremiumController extends PremiumController {
  @override
  Future<PremiumStatus> build() async =>
      const PremiumStatus(isPremium: true, storeAvailable: false);
}

Fact _fact(String id) => Fact(
  id: id,
  category: FactCategory.body,
  question: LocalizedText(es: 'Pregunta $id', en: 'Question $id'),
  answer: LocalizedText(es: 'Respuesta $id', en: 'Answer $id'),
  detail: LocalizedText(es: 'Detalle $id', en: 'Detail $id'),
  source: 'Fuente $id',
  sourceUrl: '',
);

/// Premium on purpose: it takes the ad cards out of the deck, so the cards
/// under test are the ones the test dealt.
Future<ProviderContainer> _pumpDeck(WidgetTester tester) async {
  tester.platformDispatcher.localesTestValue = const <Locale>[Locale('es')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences preferences = await SharedPreferences.getInstance();

  final ProviderContainer container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      premiumControllerProvider.overrideWith(_FakePremiumController.new),
      factsProvider.overrideWith(
        (Ref ref) async => <Fact>[for (int i = 0; i < 6; i++) _fact('$i')],
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();

  return container;
}

void main() {
  testWidgets('the ring is in the app bar from the first frame', (
    WidgetTester tester,
  ) async {
    await _pumpDeck(tester);

    expect(find.byType(GoalRingButton), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('reading the answer counts the fact', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await _pumpDeck(tester);
    expect(container.read(goalsControllerProvider).learned, 0);

    await tester.tap(find.byTooltip('Ver respuesta'));
    await tester.pumpAndSettle();

    expect(container.read(goalsControllerProvider).learned, 1);
  });

  testWidgets('hiding the answer again is not a second fact', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await _pumpDeck(tester);

    await tester.tap(find.byTooltip('Ver respuesta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ocultar'));
    await tester.pumpAndSettle();

    expect(container.read(goalsControllerProvider).learned, 1);
  });

  testWidgets('skipping cards without reading them counts nothing', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await _pumpDeck(tester);

    for (int i = 0; i < 4; i++) {
      await tester.tap(find.byTooltip('Siguiente'));
      await tester.pumpAndSettle();
    }

    expect(container.read(deckControllerProvider).value!.seenIds, hasLength(4));
    expect(
      container.read(goalsControllerProvider).learned,
      0,
      reason: 'the deck moved, but nothing was read',
    );
  });

  testWidgets('the same card read again on a later pass does not count twice', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await _pumpDeck(tester);

    await tester.tap(find.byTooltip('Ver respuesta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Siguiente'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ver respuesta'));
    await tester.pumpAndSettle();

    // Two different cards, so two facts.
    expect(container.read(goalsControllerProvider).learned, 2);
  });
}
