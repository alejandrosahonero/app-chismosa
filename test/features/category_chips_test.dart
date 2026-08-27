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

/// The chip row replaced the app bar's popup menu, so it is now the only way
/// to change category. A regression here strands the user in whatever bucket
/// they last picked.

/// Premium is forced on so `buildDeck` produces no ad slots, the inline banner
/// collapses to nothing, and no part of the tree touches the AdMob SDK.
class _FakePremiumController extends PremiumController {
  @override
  Future<PremiumStatus> build() async =>
      const PremiumStatus(isPremium: true, storeAvailable: false);
}

Fact _fact(String id, FactCategory category) => Fact(
  id: id,
  category: category,
  question: LocalizedText(es: 'Pregunta $id', en: 'Question $id'),
  answer: LocalizedText(es: 'Respuesta $id', en: 'Answer $id'),
  detail: LocalizedText(es: 'Detalle $id', en: 'Detail $id'),
  source: 'Fuente $id',
  sourceUrl: '',
);

List<Fact> _catalogue() => <Fact>[
  _fact('body1', FactCategory.body),
  _fact('body2', FactCategory.body),
  _fact('science1', FactCategory.science),
  _fact('science2', FactCategory.science),
];

/// Pumps the app on a surface wide enough to hold the whole chip row.
///
/// The row is a horizontal `ListView`, so a chip past the right edge is never
/// built and no finder can reach it. Widening the view is what puts all five
/// chips in the tree; note that `physicalSize` alone would not, because the
/// test view defaults to a device pixel ratio of 3 and the logical width is
/// what decides how many chips fit.
Future<ProviderContainer> _pumpDeck(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  tester.platformDispatcher.localesTestValue = const <Locale>[Locale('es')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences preferences = await SharedPreferences.getInstance();

  final ProviderContainer container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      premiumControllerProvider.overrideWith(_FakePremiumController.new),
      factsProvider.overrideWith((Ref ref) async => _catalogue()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const App()),
  );
  await tester.pumpAndSettle();

  return container;
}

Future<void> _tapChip(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(FilterChip, label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the row offers every category plus an all option', (
    WidgetTester tester,
  ) async {
    // A missing chip is a bucket of content the user can no longer reach, so
    // the row is asserted in full rather than sampled.
    await _pumpDeck(tester);

    for (final String label in <String>[
      'Todas',
      'Cuerpo humano',
      'Lenguaje',
      'Historia',
      'Ciencia cotidiana',
    ]) {
      expect(
        find.widgetWithText(FilterChip, label),
        findsOneWidget,
        reason: 'the "$label" chip must be in the row',
      );
    }
  });

  testWidgets('tapping a chip filters the deck to that category', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await _pumpDeck(tester);

    // The card on top must change too: the filter is worthless if the deck
    // does not follow it.
    expect(find.text('Pregunta body1'), findsOneWidget);

    await _tapChip(tester, 'Ciencia cotidiana');

    expect(container.read(categoryFilterProvider), FactCategory.science);
    expect(find.text('Pregunta science1'), findsOneWidget);
    expect(find.text('Pregunta body1'), findsNothing);
  });

  testWidgets('tapping the selected chip again keeps the filter', (
    WidgetTester tester,
  ) async {
    // `FilterChip` reports `false` on the second tap, which the row ignores on
    // purpose: on a filter row a tap means "show me this one", never "clear".
    // Honouring it would empty the filter under a user who just tapped the
    // category they are already reading.
    final ProviderContainer container = await _pumpDeck(tester);

    await _tapChip(tester, 'Ciencia cotidiana');
    await _tapChip(tester, 'Ciencia cotidiana');

    expect(container.read(categoryFilterProvider), FactCategory.science);
    expect(find.text('Pregunta science1'), findsOneWidget);
  });

  testWidgets('the all chip clears the filter', (WidgetTester tester) async {
    // The only way back to the whole catalogue.
    final ProviderContainer container = await _pumpDeck(tester);

    await _tapChip(tester, 'Ciencia cotidiana');
    expect(container.read(categoryFilterProvider), FactCategory.science);

    await _tapChip(tester, 'Todas');

    expect(container.read(categoryFilterProvider), isNull);
    expect(find.text('Pregunta body1'), findsOneWidget);
  });
}
