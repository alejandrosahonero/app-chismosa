library;

import 'package:aja/app.dart';
import 'package:aja/features/facts/domain/fact.dart';
import 'package:aja/features/facts/presentation/providers/facts_providers.dart';
import 'package:aja/features/facts/presentation/providers/favorites_controller.dart';
import 'package:aja/services/billing/premium_controller.dart';
import 'package:aja/services/billing/premium_state.dart';
import 'package:aja/services/storage/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Favourites are sold as part of the one-off `premium_remove_ads` purchase.
///
/// The gate is the revenue: if a free user can save a card, the feature is
/// given away, and if a paying user cannot, it is a refund and a 1-star review.
/// Both directions are asserted here.

class _FakePremiumController extends PremiumController {
  _FakePremiumController({required this.isPremium});

  final bool isPremium;

  @override
  Future<PremiumStatus> build() async =>
      PremiumStatus(isPremium: isPremium, storeAvailable: false);
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

/// Pumps the app and returns the container, so a test can read the favourites
/// state without going through the widget tree.
Future<ProviderContainer> _pumpDeck(
  WidgetTester tester, {
  required bool isPremium,
}) async {
  tester.platformDispatcher.localesTestValue = const <Locale>[Locale('es')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences preferences = await SharedPreferences.getInstance();

  final ProviderContainer container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      premiumControllerProvider.overrideWith(
        () => _FakePremiumController(isPremium: isPremium),
      ),
      factsProvider.overrideWith(
        (Ref ref) async => <Fact>[_fact('1'), _fact('2')],
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
  testWidgets('a free user gets the paywall pitch instead of saving', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await _pumpDeck(
      tester,
      isPremium: false,
    );

    await tester.tap(find.byTooltip('Guardar esta tarjeta'));
    await tester.pumpAndSettle();

    expect(find.text('Función premium'), findsOneWidget);
    expect(container.read(favoritesProvider), isEmpty);
  });

  testWidgets('dismissing the pitch leaves the user where they were', (
    WidgetTester tester,
  ) async {
    await _pumpDeck(tester, isPremium: false);

    await tester.tap(find.byTooltip('Guardar esta tarjeta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ahora no'));
    await tester.pumpAndSettle();

    expect(find.text('Función premium'), findsNothing);
    expect(find.text('Pregunta 1'), findsOneWidget);
  });

  testWidgets('a premium user saves the card and can unsave it', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await _pumpDeck(
      tester,
      isPremium: true,
    );

    await tester.tap(find.byTooltip('Guardar esta tarjeta'));
    await tester.pumpAndSettle();

    expect(container.read(favoritesProvider), contains('1'));
    expect(find.text('Función premium'), findsNothing);
    // The button flips to the "remove" affordance once saved.
    expect(find.byTooltip('Quitar de guardadas'), findsOneWidget);

    await tester.tap(find.byTooltip('Quitar de guardadas'));
    await tester.pumpAndSettle();

    expect(container.read(favoritesProvider), isEmpty);
  });

  testWidgets('swiping the card up saves it for a premium user', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await _pumpDeck(
      tester,
      isPremium: true,
    );

    // Straight up and far enough to clear the commit threshold. The card must
    // stay put: saving is not a reason to stop reading it.
    await tester.drag(find.text('Pregunta 1'), const Offset(0, -260));
    await tester.pumpAndSettle();

    expect(container.read(favoritesProvider), contains('1'));
    expect(find.text('Pregunta 1'), findsOneWidget);
  });

  testWidgets('a downward swipe does nothing', (WidgetTester tester) async {
    final ProviderContainer container = await _pumpDeck(
      tester,
      isPremium: true,
    );

    await tester.drag(find.text('Pregunta 1'), const Offset(0, 260));
    await tester.pumpAndSettle();

    expect(container.read(favoritesProvider), isEmpty);
    expect(find.text('Pregunta 1'), findsOneWidget);
  });
}
