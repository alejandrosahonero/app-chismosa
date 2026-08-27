import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aja/core/errors/app_exception.dart';
import 'package:aja/core/theme/app_colors.dart';
import 'package:aja/features/facts/domain/fact.dart';
import 'package:flutter/material.dart';

/// Every string that goes on the shared image, already resolved.
///
/// The renderer never sees a [BuildContext]: it is driven from a service, and
/// a localized string looked up mid-render is a string looked up after the
/// widget that owned the context may already be gone.
@immutable
class FactStoryLabels {
  const FactStoryLabels({
    required this.appName,
    required this.tagline,
    required this.category,
    required this.callToAction,
  });

  final String appName;
  final String tagline;
  final String category;

  /// The hook, printed under the question. The answer is deliberately *not* on
  /// the image: it is the reason to install the app.
  final String callToAction;
}

/// Rasterizes a fact as a 9:16 image ready to post.
///
/// 1080x1920 is the native canvas of an Instagram story, a Reel and a TikTok
/// post, so nothing is re-encoded or cropped on upload. All three paint their
/// own chrome over the top and bottom of that canvas — profile row, caption,
/// progress bars, the right-hand action rail — which is why the artwork lives
/// inside [_safeTop] / [_safeBottom] instead of filling the frame.
///
/// Painted straight onto a [Canvas] rather than rasterized from a widget: the
/// output has to be exactly 1080x1920 whatever the phone's screen size, density
/// or theme is, and a `RepaintBoundary` gives you the device's pixels instead.
abstract final class FactStoryImage {
  static const double canvasWidth = 1080;
  static const double canvasHeight = 1920;

  /// Bands reserved for the host app's own interface.
  static const double _safeTop = 300;
  static const double _safeBottom = 380;

  static const double _margin = 90;

  /// The card, and the wordmark under it, live entirely inside the safe band.
  static const double _cardTop = _safeTop + 60;
  static const double _cardHeight =
      canvasHeight - _cardTop - _safeBottom - _wordmarkHeight;

  /// Room under the card for the app name and its tagline.
  static const double _wordmarkHeight = 200;
  static const double _cardPadding = 80;
  static const double _cardRadius = 64;

  /// The question shrinks to fit rather than the card growing to hold it: a
  /// fixed frame is what makes a feed of these look like one series.
  static const double _questionMaxSize = 76;
  static const double _questionMinSize = 34;
  static const double _questionHeightFactor = 1.25;

  /// Brand colours, seeded exactly like the app's theme so that re-branding
  /// through [AppColors.seed] carries over to everything shared.
  ///
  /// Fixed to the light scheme on purpose: a shared image is not the user's
  /// screen, and a post whose background changes with the reader's theme
  /// setting reads as two different accounts.
  static final ColorScheme _brand = ColorScheme.fromSeed(
    seedColor: AppColors.seed,
  );

  static final Color _backgroundTop = Color.lerp(
    AppColors.seed,
    Colors.black,
    0.45,
  )!;
  static final Color _backgroundBottom = Color.lerp(
    AppColors.seed,
    Colors.black,
    0.86,
  )!;

  /// PNG bytes of [fact]'s question, in [language].
  ///
  /// Throws [DataException] if the engine cannot encode the frame, which is the
  /// only failure mode here worth telling the user about.
  static Future<Uint8List> render({
    required Fact fact,
    required String language,
    required FactStoryLabels labels,
  }) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
    );

    // Held until after the frame is encoded: the painters own the native
    // paragraphs the recorded picture draws from, so they cannot be released
    // while the picture is still being rasterized.
    final List<TextPainter> painters = _paint(
      canvas,
      question: fact.question.resolve(language),
      labels: labels,
    );

    final ui.Picture picture = recorder.endRecording();
    try {
      final ui.Image image = await picture.toImage(
        canvasWidth.round(),
        canvasHeight.round(),
      );
      try {
        final ByteData? data = await image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (data == null) {
          throw const DataException('The share image could not be encoded.');
        }
        return data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
      for (final TextPainter painter in painters) {
        painter.dispose();
      }
    }
  }

  static List<TextPainter> _paint(
    Canvas canvas, {
    required String question,
    required FactStoryLabels labels,
  }) {
    _paintBackground(canvas);

    const Rect card = Rect.fromLTWH(
      _margin,
      _cardTop,
      canvasWidth - _margin * 2,
      _cardHeight,
    );
    _paintCard(canvas, card);

    final double contentLeft = card.left + _cardPadding;
    final double contentWidth = card.width - _cardPadding * 2;

    final TextPainter category = _paintCategoryPill(
      canvas,
      labels.category,
      Offset(contentLeft, card.top + _cardPadding),
    );

    final TextPainter callToAction = _layout(
      labels.callToAction,
      TextStyle(
        color: _brand.primary,
        fontSize: 38,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
      contentWidth,
    );

    // What is left for the question once the pill and the hook have taken
    // their share, with a gap on each side of it.
    final double questionTop = card.top + _cardPadding + _pillHeight + 72;
    final double questionBottom =
        card.bottom - _cardPadding - callToAction.height - 56;

    final TextPainter title = _fitQuestion(
      question,
      contentWidth,
      questionBottom - questionTop,
    );

    // Centred in its band, so a one-line question and a five-line one both sit
    // where the eye expects them.
    title.paint(
      canvas,
      Offset(
        contentLeft,
        questionTop + (questionBottom - questionTop - title.height) / 2,
      ),
    );
    callToAction.paint(
      canvas,
      Offset(contentLeft, card.bottom - _cardPadding - callToAction.height),
    );

    final List<TextPainter> wordmark = _paintWordmark(canvas, labels);

    return <TextPainter>[category, title, callToAction, ...wordmark];
  }

  static void _paintBackground(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(canvasWidth, canvasHeight),
          <Color>[_backgroundTop, _backgroundBottom],
        ),
    );

    // Two soft blooms. Flat colour at this size looks like a rendering bug on a
    // feed full of photographs.
    canvas
      ..drawCircle(
        const Offset(canvasWidth * 0.88, canvasHeight * 0.1),
        340,
        Paint()..color = Colors.white.withValues(alpha: 0.07),
      )
      ..drawCircle(
        const Offset(canvasWidth * 0.08, canvasHeight * 0.88),
        280,
        Paint()..color = Colors.white.withValues(alpha: 0.05),
      );
  }

  static void _paintCard(Canvas canvas, Rect card) {
    final RRect shape = RRect.fromRectAndRadius(
      card,
      const Radius.circular(_cardRadius),
    );

    canvas
      ..drawRRect(
        shape.shift(const Offset(0, 20)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.32)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28),
      )
      ..drawRRect(shape, Paint()..color = _brand.surface);
  }

  /// The category, as the small pill the front of the card also wears.
  static TextPainter _paintCategoryPill(
    Canvas canvas,
    String label,
    Offset topLeft,
  ) {
    final TextPainter painter = _layout(
      label.toUpperCase(),
      TextStyle(
        color: _brand.onPrimaryContainer,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: 2.4,
      ),
      canvasWidth,
    );

    const double paddingX = 32;
    final Rect pill = Rect.fromLTWH(
      topLeft.dx,
      topLeft.dy,
      painter.width + paddingX * 2,
      _pillHeight,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(pill, const Radius.circular(_pillHeight / 2)),
      Paint()..color = _brand.primaryContainer,
    );
    painter.paint(
      canvas,
      Offset(
        pill.left + paddingX,
        pill.top + (_pillHeight - painter.height) / 2,
      ),
    );

    return painter;
  }

  static const double _pillHeight = 64;

  /// App name and tagline under the card, so the post is attributable even
  /// after someone screenshots it out of context.
  static List<TextPainter> _paintWordmark(
    Canvas canvas,
    FactStoryLabels labels,
  ) {
    final TextPainter name = _layout(
      labels.appName,
      const TextStyle(
        color: Colors.white,
        fontSize: 68,
        fontWeight: FontWeight.w800,
        letterSpacing: -1,
      ),
      canvasWidth,
    );
    final TextPainter tagline = _layout(
      labels.tagline.toUpperCase(),
      TextStyle(
        color: Colors.white.withValues(alpha: 0.72),
        fontSize: 26,
        fontWeight: FontWeight.w600,
        letterSpacing: 4,
      ),
      canvasWidth,
    );

    const double top = _cardTop + _cardHeight + 60;
    name.paint(canvas, Offset((canvasWidth - name.width) / 2, top));
    tagline.paint(
      canvas,
      Offset((canvasWidth - tagline.width) / 2, top + name.height + 18),
    );

    return <TextPainter>[name, tagline];
  }

  /// Largest size at which the question still fits its band.
  static TextPainter _fitQuestion(
    String question,
    double maxWidth,
    double maxHeight,
  ) {
    for (double size = _questionMaxSize; size > _questionMinSize; size -= 2) {
      final TextPainter painter = _layout(
        question,
        _questionStyle(size),
        maxWidth,
      );
      if (painter.height <= maxHeight) return painter;
      painter.dispose();
    }

    // A question that does not fit at 34pt is a content bug, but the share must
    // still produce a valid image, so the tail is cut instead of spilling out
    // of the card.
    return _layout(
      question,
      _questionStyle(_questionMinSize),
      maxWidth,
      maxLines: (maxHeight / (_questionMinSize * _questionHeightFactor))
          .floor()
          .clamp(1, 99),
      ellipsis: '…',
    );
  }

  static TextStyle _questionStyle(double size) => TextStyle(
    color: _brand.onSurface,
    fontSize: size,
    fontWeight: FontWeight.w700,
    height: _questionHeightFactor,
  );

  static TextPainter _layout(
    String text,
    TextStyle style,
    double maxWidth, {
    int? maxLines,
    String? ellipsis,
  }) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: ellipsis,
    )..layout(maxWidth: maxWidth);
  }
}
