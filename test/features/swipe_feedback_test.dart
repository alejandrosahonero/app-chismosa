library;

import 'package:aja/app.dart';
import 'package:aja/features/facts/domain/fact.dart';
import 'package:aja/features/facts/presentation/providers/facts_providers.dart';
import 'package:aja/features/facts/presentation/widgets/swipe_deck.dart';
import 'package:aja/services/billing/premium_controller.dart';
import 'package:aja/services/billing/premium_state.dart';
import 'package:aja/services/storage/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The swipe feedback system — badge fade-in and button zoom — is a visual
/// signal of which action a mid-drag gesture will fire. It must be correct,
/// because wrong feedback is worse than no feedback: it trains the user to
/// expect the opposite action.

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

/// Pumps the app and returns the container, so a test can read state without
/// going through the widget tree.
Future<ProviderContainer> _pumpDeck(WidgetTester tester) async {
  tester.platformDispatcher.localesTestValue = const <Locale>[Locale('es')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences preferences = await SharedPreferences.getInstance();

  final ProviderContainer container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      premiumControllerProvider.overrideWith(
        () => _FakePremiumController(isPremium: true),
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

/// Scale currently applied to the round control carrying [tooltip].
double _buttonScale(WidgetTester tester, String tooltip) {
  final Transform transform = tester.widget<Transform>(
    find
        .descendant(
          of: find.byTooltip(tooltip),
          matching: find.byType(Transform),
        )
        .first,
  );
  return transform.transform.getMaxScaleOnAxis();
}

void main() {
  testWidgets('a leftward drag grows the skip button', (
    WidgetTester tester,
  ) async {
    // When the user's finger moves left, the skip button must swell to
    // announce the action. The growth must be monotonic — moving further
    // left makes it bigger — and capped at 1.4x so the buttons never collide.
    await _pumpDeck(tester);

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('Pregunta 1')),
    );

    // At rest, no zoom.
    expect(_buttonScale(tester, 'Siguiente'), moreOrLessEquals(1.0));

    // Prime move along the same axis wins the gesture arena.
    // DragStartBehavior.start consumes this travel in onPanStart.
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();

    // After a substantial leftward move, it grows.
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();
    final double firstScale = _buttonScale(tester, 'Siguiente');
    expect(firstScale, greaterThan(1.0));

    // Moving further left makes it bigger still.
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();
    final double secondScale = _buttonScale(tester, 'Siguiente');
    expect(secondScale, greaterThan(firstScale));
    expect(secondScale, lessThanOrEqualTo(1.4));

    // The other buttons must stay at rest.
    expect(_buttonScale(tester, 'Ver respuesta'), moreOrLessEquals(1.0));
    expect(_buttonScale(tester, 'Guardar esta tarjeta'), moreOrLessEquals(1.0));
    expect(
      _buttonScale(tester, 'Compartir la pregunta'),
      moreOrLessEquals(1.0),
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'a leftward drag puts the skip badge on the far edge of the card',
    (WidgetTester tester) async {
      // The badge floats on the edge that stays on screen as the card leaves.
      // For a leftward drag, the card slides off the left, so the badge sits
      // on the right. If it rode on the left, it would disappear exactly when
      // confirming the action.
      await _pumpDeck(tester);

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.text('Pregunta 1')),
      );

      // Prime move to win the gesture arena.
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();

      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump();

      // The badge and button both have the skip icon, so we get two matches.
      final Finder skipIcons = find.byIcon(Icons.close_rounded);
      expect(skipIcons, findsWidgets);

      final Offset cardCenter = tester.getCenter(find.byType(SwipeDeck));
      final List<Offset> iconCenters = <Offset>[
        for (int i = 0; i < skipIcons.evaluate().length; i++)
          tester.getCenter(skipIcons.at(i)),
      ];

      // At least one icon (the badge) must be right of the card's centre.
      expect(iconCenters.any((Offset pos) => pos.dx > cardCenter.dx), isTrue);

      // Share button must stay at rest.
      expect(
        _buttonScale(tester, 'Compartir la pregunta'),
        moreOrLessEquals(1.0),
      );

      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('a rightward drag grows the flip button and no other', (
    WidgetTester tester,
  ) async {
    // The dominant axis must fire alone. If both horizontal and vertical
    // buttons grew at once, the gesture would be ambiguous.
    await _pumpDeck(tester);

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('Pregunta 1')),
    );

    // Prime move along the same axis wins the gesture arena.
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();

    // Flip (right) must grow.
    expect(_buttonScale(tester, 'Ver respuesta'), greaterThan(1.0));

    // Skip (left), favourite (up), and share (down) must stay at rest.
    expect(_buttonScale(tester, 'Siguiente'), moreOrLessEquals(1.0));
    expect(_buttonScale(tester, 'Guardar esta tarjeta'), moreOrLessEquals(1.0));
    expect(
      _buttonScale(tester, 'Compartir la pregunta'),
      moreOrLessEquals(1.0),
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('an upward drag grows the favourite button and no other', (
    WidgetTester tester,
  ) async {
    // Like the rightward case: only the dominant axis fires. A gesture that
    // moves 200 px up and 40 px left is an upward swipe, not a dismissal.
    await _pumpDeck(tester);

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('Pregunta 1')),
    );

    // Prime move along the same axis wins the gesture arena.
    // Up threshold (0.16 of height) is smaller, so use larger real move.
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();

    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();

    // Favourite (up) must grow.
    expect(_buttonScale(tester, 'Guardar esta tarjeta'), greaterThan(1.0));

    // Skip (left), flip (right), and share (down) must stay at rest.
    expect(_buttonScale(tester, 'Siguiente'), moreOrLessEquals(1.0));
    expect(_buttonScale(tester, 'Ver respuesta'), moreOrLessEquals(1.0));
    expect(
      _buttonScale(tester, 'Compartir la pregunta'),
      moreOrLessEquals(1.0),
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a downward drag grows the share button', (
    WidgetTester tester,
  ) async {
    // Downward drag shares the question. Like the upward gesture, it returns
    // the card to the centre without dismissing it.
    await _pumpDeck(tester);

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('Pregunta 1')),
    );

    // Prime move along the same axis wins the gesture arena.
    // Down threshold (0.26 of height) requires substantial movement.
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();

    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();

    // Share (down) must grow.
    expect(_buttonScale(tester, 'Compartir la pregunta'), greaterThan(1.0));

    // The other three buttons must stay at rest.
    expect(_buttonScale(tester, 'Siguiente'), moreOrLessEquals(1.0));
    expect(_buttonScale(tester, 'Ver respuesta'), moreOrLessEquals(1.0));
    expect(_buttonScale(tester, 'Guardar esta tarjeta'), moreOrLessEquals(1.0));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('releasing the card returns every button to its resting size', (
    WidgetTester tester,
  ) async {
    // The spring-back animation uses Curves.easeOutBack, which overshoots
    // the centre and briefly flips the sign of the drag. If not guarded,
    // this would blink the badge and button of the opposite action at the end
    // of every gesture, training the user to expect the wrong thing. Only the
    // direction the user released towards is allowed to show.
    await _pumpDeck(tester);

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.text('Pregunta 1')),
    );

    // Prime move along the same axis wins the gesture arena.
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();

    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();

    // Button is zoomed mid-drag.
    expect(_buttonScale(tester, 'Siguiente'), greaterThan(1.0));

    await gesture.up();
    await tester.pumpAndSettle();

    // After settling, all four buttons are back at 1.0 (no overshoot blink).
    expect(_buttonScale(tester, 'Siguiente'), moreOrLessEquals(1.0));
    expect(_buttonScale(tester, 'Ver respuesta'), moreOrLessEquals(1.0));
    expect(_buttonScale(tester, 'Guardar esta tarjeta'), moreOrLessEquals(1.0));
    expect(
      _buttonScale(tester, 'Compartir la pregunta'),
      moreOrLessEquals(1.0),
    );
  });
}
