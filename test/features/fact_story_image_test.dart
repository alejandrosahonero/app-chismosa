library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aja/features/facts/data/fact_story_image.dart';
import 'package:aja/features/facts/domain/fact.dart';
import 'package:flutter_test/flutter_test.dart';

/// The share image is the app's only marketing surface: every post is a 9:16
/// frame that Instagram and TikTok accept without re-encoding it. A wrong size
/// gets letterboxed or cropped through the question, so the geometry is
/// asserted rather than eyeballed.
///
/// Note for anyone extending this file: rendering goes through the engine, so
/// it cannot run inside `testWidgets`' fake clock — a plain `test` (or
/// `tester.runAsync`) is required or the future never completes.

const FactStoryLabels _labels = FactStoryLabels(
  appName: 'Ajá',
  tagline: 'Datos curiosos raros',
  category: 'Ciencia',
  callToAction: '¿Sabes la respuesta?',
);

Fact _fact(String question) => Fact(
  id: 'story-1',
  category: FactCategory.science,
  question: LocalizedText(es: question, en: 'English $question'),
  answer: const LocalizedText(es: 'Respuesta', en: 'Answer'),
  detail: const LocalizedText(es: 'Detalle', en: 'Detail'),
  source: 'Fuente',
  sourceUrl: '',
);

Future<ui.Image> _decode(Uint8List png) async {
  final ui.Codec codec = await ui.instantiateImageCodec(png);
  final ui.FrameInfo frame = await codec.getNextFrame();
  return frame.image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders exactly the canvas the story surfaces expect', () async {
    final Uint8List png = await FactStoryImage.render(
      fact: _fact('¿Por qué el cielo es azul?'),
      language: 'es',
      labels: _labels,
    );

    final ui.Image image = await _decode(png);
    addTearDown(image.dispose);

    expect(image.width, 1080);
    expect(image.height, 1920);
  });

  test(
    'a question far longer than the card still produces a valid image',
    () async {
      // The auto-fit shrinks the question and, past its floor, cuts the tail. It
      // must never overflow the card or fail to encode: a share that throws is a
      // share the user simply cannot make.
      final Uint8List png = await FactStoryImage.render(
        fact: _fact('¿Por qué motivo exacto ${'y muy largo ' * 80}?'),
        language: 'es',
        labels: _labels,
      );

      final ui.Image image = await _decode(png);
      addTearDown(image.dispose);

      expect(image.width, 1080);
      expect(image.height, 1920);
    },
  );

  test('the frame is actually painted, not a blank canvas', () async {
    final Uint8List png = await FactStoryImage.render(
      fact: _fact('¿Cuánto pesa una nube?'),
      language: 'es',
      labels: _labels,
    );

    final ui.Image image = await _decode(png);
    addTearDown(image.dispose);

    final ByteData? pixels = await image.toByteData();
    expect(pixels, isNotNull);

    // The card is near-white and the background is a dark gradient, so a frame
    // that painted correctly has both a light and a dark pixel in it. A single
    // flat colour means the canvas was recorded but nothing landed on it.
    final int card = pixels!.getUint32(_pixelOffset(540, 900));
    final int background = pixels.getUint32(_pixelOffset(30, 30));
    expect(card, isNot(background));
    expect(_luminance(card), greaterThan(_luminance(background)));
  });

  test('the question is read in the requested language', () async {
    // Both renders must succeed and differ: the catalogue ships every string in
    // both languages, and sharing the Spanish copy to an English user would be
    // a silent content bug.
    final Fact fact = _fact('¿Cuántos huesos tiene un tiburón?');

    final Uint8List es = await FactStoryImage.render(
      fact: fact,
      language: 'es',
      labels: _labels,
    );
    final Uint8List en = await FactStoryImage.render(
      fact: fact,
      language: 'en',
      labels: _labels,
    );

    expect(es, isNot(equals(en)));
  });
}

int _pixelOffset(int x, int y) => (y * 1080 + x) * 4;

/// Rough perceived brightness of an RGBA word, enough to tell the card from the
/// background without pulling in a colour library.
int _luminance(int rgba) {
  final int r = (rgba >> 24) & 0xFF;
  final int g = (rgba >> 16) & 0xFF;
  final int b = (rgba >> 8) & 0xFF;
  return (r * 299 + g * 587 + b * 114) ~/ 1000;
}
