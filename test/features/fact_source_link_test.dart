/// The citation under every answer.
///
/// The catalogue ships a permanent link for every fact that survived
/// verification, so the line has to be openable — and it has to stay a plain
/// label for an entry that arrives from the remote catalogue without one,
/// rather than offering a link that goes nowhere.

library;

import 'package:aja/app.dart';
import 'package:aja/features/facts/domain/fact.dart';
import 'package:aja/features/facts/presentation/providers/deck_controller.dart';
import 'package:aja/features/facts/presentation/providers/facts_providers.dart';
import 'package:aja/features/facts/presentation/widgets/fact_source_link.dart';
import 'package:aja/l10n/generated/app_localizations.dart';
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

Fact _fact({required String sourceUrl}) => Fact(
  id: 'test',
  category: FactCategory.body,
  question: const LocalizedText(es: 'Pregunta', en: 'Question'),
  answer: const LocalizedText(es: 'Respuesta', en: 'Answer'),
  detail: const LocalizedText(es: 'Detalle', en: 'Detail'),
  source: 'MedlinePlus',
  sourceUrl: sourceUrl,
);

Future<void> _pumpLink(WidgetTester tester, String url) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: FactSourceLink(source: 'MedlinePlus', url: url),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an entry without a link is plain text', (
    WidgetTester tester,
  ) async {
    await _pumpLink(tester, '');

    expect(find.textContaining('MedlinePlus'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsNothing);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('an entry with a link is announced as one', (
    WidgetTester tester,
  ) async {
    await _pumpLink(tester, 'https://medlineplus.gov/ency/article/003117.htm');

    expect(find.textContaining('MedlinePlus'), findsOneWidget);
    // The underline alone reads as emphasis on a label this small; the icon is
    // what tells the user the tap leaves the app.
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    expect(find.byType(InkWell), findsOneWidget);

    final Semantics semantics = tester.widget<Semantics>(
      find
          .ancestor(of: find.byType(InkWell), matching: find.byType(Semantics))
          .first,
    );
    expect(semantics.properties.link, isTrue);
  });

  testWidgets('tapping the source does not flip the card back', (
    WidgetTester tester,
  ) async {
    // The back of the card is itself a tap target that flips it. The inner
    // gesture has to win the arena, or reading a source would close it.
    tester.platformDispatcher.localesTestValue = const <Locale>[Locale('es')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    final ProviderContainer container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        premiumControllerProvider.overrideWith(_FakePremiumController.new),
        factsProvider.overrideWith(
          (Ref ref) async => <Fact>[
            _fact(sourceUrl: 'https://medlineplus.gov/ency/article/003117.htm'),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const App()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ver respuesta'));
    await tester.pumpAndSettle();
    expect(container.read(deckControllerProvider).value!.revealed, isTrue);

    await tester.tap(find.byIcon(Icons.open_in_new));
    await tester.pumpAndSettle();

    expect(container.read(deckControllerProvider).value!.revealed, isTrue);
  });
}
