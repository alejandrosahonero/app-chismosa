/// "Me gustaron" and the share image.
library;

import 'dart:ui' as ui;

import 'package:chismosa/features/stories/data/story_share_image.dart';
import 'package:chismosa/features/stories/domain/feed_query.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('"me gustaron" is a different deck, not the same one', () {
    const FeedQuery deck = FeedQuery(countryCode: 'ES');
    final FeedQuery liked = deck.copyWith(liked: true);
    expect(liked, isNot(deck));
    expect(liked.countryCode, 'ES');
    expect(liked.copyWith(liked: false), deck);
  });

  testWidgets('the share image is exactly 1080x1920, whatever the story', (
    WidgetTester tester,
  ) async {
    // The render goes through the engine and hangs under the fake clock.
    await tester.runAsync(() async {
      for (final String body in <String>[
        'Corta.',
        List<String>.filled(60, 'Historia larguísima que no cabe').join(' '),
      ]) {
        final Uint8List png = await StoryShareImage.render(
          body: body,
          cta: '¿Y tú qué opinas?',
          link: 'chismosa.pages.dev/s/x',
          tag: 'Parte 2',
        );
        final ui.Codec codec = await ui.instantiateImageCodec(png);
        final ui.FrameInfo frame = await codec.getNextFrame();
        expect(frame.image.width, 1080);
        expect(frame.image.height, 1920);
        frame.image.dispose();
      }
    });
  });
}
