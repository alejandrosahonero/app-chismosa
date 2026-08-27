library;

import 'package:aja/app.dart';
import 'package:aja/features/facts/domain/fact.dart';
import 'package:aja/features/facts/presentation/providers/facts_providers.dart';
import 'package:aja/services/billing/premium_controller.dart';
import 'package:aja/services/billing/premium_state.dart';
import 'package:aja/services/storage/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// End to end test of the only screen the app has.
///
/// The two gestures are the product, so a regression here is a broken app: the
/// front must never leak the answer, and a new card must never come up already
/// flipped.

/// Premium is forced on so `buildDeck` produces no ad slots and nothing in the
/// tree ever touches the AdMob SDK.
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

/// Pumps the real app with a fixed catalogue.
///
/// The locale is pinned to Spanish: the default test locale is `en`, and an
/// unpinned locale would silently switch both the UI strings and the card
/// content to the other language.
Future<void> _pumpDeck(WidgetTester tester) async {
  tester.platformDispatcher.localesTestValue = const <Locale>[Locale('es')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences preferences = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        premiumControllerProvider.overrideWith(_FakePremiumController.new),
        factsProvider.overrideWith(
          (Ref ref) async => <Fact>[_fact('1'), _fact('2'), _fact('3')],
        ),
      ],
      child: const App(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the front of the card shows the question, never the answer', (
    WidgetTester tester,
  ) async {
    await _pumpDeck(tester);

    expect(find.text('Pregunta 1'), findsOneWidget);
    expect(find.text('Respuesta 1', skipOffstage: false), findsNothing);
  });

  testWidgets('revealing the card shows the answer and its source', (
    WidgetTester tester,
  ) async {
    await _pumpDeck(tester);

    await tester.tap(find.byTooltip('Ver respuesta'));
    await tester.pumpAndSettle();

    expect(find.text('Respuesta 1'), findsOneWidget);
    expect(find.text('Fuente: Fuente 1'), findsOneWidget);
    // The question is on the other face and must be gone once flipped.
    expect(find.text('Pregunta 1'), findsNothing);
  });

  testWidgets('advancing brings up the next card, unflipped', (
    WidgetTester tester,
  ) async {
    await _pumpDeck(tester);

    await tester.tap(find.byTooltip('Ver respuesta'));
    await tester.pumpAndSettle();
    expect(find.text('Respuesta 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Siguiente'));
    await tester.pumpAndSettle();

    expect(find.text('Pregunta 2'), findsOneWidget);
    // A card must never arrive already showing its answer.
    expect(find.text('Respuesta 2'), findsNothing);
    expect(find.text('Respuesta 1'), findsNothing);
  });
}
