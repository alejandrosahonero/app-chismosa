import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chismosa/core/theme/app_colors.dart';
import 'package:chismosa/core/theme/app_theme.dart';
import 'package:flutter/painting.dart';

/// Paints a story as a 1080x1920 PNG: the native size of an Instagram story,
/// a Reel and a TikTok, so it posts without cropping or re-encoding.
///
/// Drawn on a [Canvas], not by rasterising a widget: it has to measure exactly
/// 1080x1920 whatever the phone's size, density and theme, and it is always the
/// dark brand frame — a post whose colours change with the reader's theme looks
/// like it came from two different accounts.
///
/// Everything readable sits inside the platforms' safe area (roughly the middle
/// 1420 px): Instagram and TikTok draw their own UI over the top and bottom
/// strips.
abstract final class StoryShareImage {
  static const double width = 1080;
  static const double height = 1920;

  /// The story shrinks to fit a fixed card, never the other way round: the
  /// constant frame is what makes a feed of these read as one series. Past the
  /// minimum it is cut with an ellipsis — "read the rest in the app" is the
  /// whole point of the post anyway.
  static const double _maxFont = 66;
  static const double _minFont = 40;

  static Future<Uint8List> render({
    required String body,
    required String cta,
    required String link,
    String? tag,
  }) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, width, height),
    );
    paint(canvas, body: body, cta: cta, link: link, tag: tag);
    final ui.Image image = await recorder.endRecording().toImage(
      width.toInt(),
      height.toInt(),
    );
    final ByteData? bytes = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  static void paint(
    Canvas canvas, {
    required String body,
    required String cta,
    required String link,
    String? tag,
  }) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, width, height),
      Paint()..color = AppColors.ink,
    );

    // Header: the mark and the wordmark.
    drawMark(canvas, const Offset(96, 262), 120);
    _text(
      canvas,
      'Chismosa',
      const Offset(236, 272),
      const TextStyle(
        fontFamily: AppFonts.display,
        fontWeight: FontWeight.w800,
        fontSize: 68,
        letterSpacing: -2,
        color: AppColors.paper,
      ),
    );

    // The card: a note on the table.
    const Rect card = Rect.fromLTRB(72, 440, 1008, 1500);
    canvas.drawRRect(
      RRect.fromRectAndRadius(card, const Radius.circular(64)),
      Paint()..color = AppColors.paper,
    );

    double top = card.top + 56;
    if (tag != null) {
      final TextPainter pill = _layout(
        tag,
        const TextStyle(
          fontFamily: AppFonts.body,
          fontWeight: FontWeight.w800,
          fontSize: 34,
          color: Color(0xFF1B2200),
        ),
        maxWidth: 600,
      );
      final Rect pillRect = Rect.fromLTWH(
        card.left + 64,
        top,
        pill.width + 48,
        pill.height + 20,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(pillRect, const Radius.circular(40)),
        Paint()..color = AppColors.lime,
      );
      pill.paint(canvas, Offset(pillRect.left + 24, pillRect.top + 10));
      top = pillRect.bottom + 24;
    }

    _text(
      canvas,
      '“',
      Offset(card.left + 56, top - 30),
      const TextStyle(
        fontFamily: AppFonts.display,
        fontWeight: FontWeight.w800,
        fontSize: 220,
        height: 1,
        color: AppColors.spice,
      ),
    );

    final double textTop = top + 150;
    final double available = card.bottom - 72 - textTop;
    const double textWidth = 800;
    final TextPainter story = _fit(body, textWidth, available);
    story.paint(canvas, Offset(card.left + 68, textTop));

    // Footer: the question that sends people to the thread, and where.
    final TextPainter question = _layout(
      cta,
      const TextStyle(
        fontFamily: AppFonts.display,
        fontWeight: FontWeight.w800,
        fontSize: 56,
        letterSpacing: -1,
        color: AppColors.paper,
      ),
      maxWidth: 936,
      align: TextAlign.center,
    );
    question.paint(canvas, Offset((width - question.width) / 2, 1560));
    final TextPainter url = _layout(
      link,
      const TextStyle(
        fontFamily: AppFonts.body,
        fontWeight: FontWeight.w600,
        fontSize: 38,
        color: AppColors.lavender,
      ),
      maxWidth: 936,
      align: TextAlign.center,
    );
    url.paint(
      canvas,
      Offset((width - url.width) / 2, 1560 + question.height + 18),
    );
  }

  /// The largest size between [_minFont] and [_maxFont] at which the story fits
  /// [maxHeight]; at the minimum, cut with an ellipsis.
  static TextPainter _fit(String body, double maxWidth, double maxHeight) {
    for (double size = _maxFont; size >= _minFont; size -= 2) {
      final TextPainter painter = _layout(
        body,
        _storyStyle(size),
        maxWidth: maxWidth,
      );
      if (painter.height <= maxHeight) return painter;
    }
    final TextStyle style = _storyStyle(_minFont);
    final int lines = math.max(
      1,
      (maxHeight / (_minFont * (style.height ?? 1.2))).floor(),
    );
    return _layout(body, style, maxWidth: maxWidth, maxLines: lines);
  }

  static TextStyle _storyStyle(double size) => TextStyle(
    fontFamily: AppFonts.body,
    fontWeight: FontWeight.w700,
    fontSize: size,
    height: 1.28,
    letterSpacing: -0.5,
    color: AppColors.ink,
  );

  static TextPainter _layout(
    String text,
    TextStyle style, {
    required double maxWidth,
    int? maxLines,
    TextAlign align = TextAlign.start,
  }) {
    return TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…',
    )..layout(maxWidth: maxWidth);
  }

  static void _text(Canvas canvas, String text, Offset at, TextStyle style) {
    _layout(text, style, maxWidth: width).paint(canvas, at);
  }

  /// The brand mark — "la burbuja cómplice" — at [origin] (top-left) and
  /// [size] px square. Same geometry as `brand/logo.svg`, whose bubble lives in
  /// the 28..80 × 32..83 part of a 108 grid.
  static void drawMark(Canvas canvas, Offset origin, double size) {
    final double k = size / 56;
    Offset p(double x, double y) =>
        Offset(origin.dx + (x - 26) * k, origin.dy + (y - 30) * k);

    final Path bubble = Path()
      ..moveTo(p(46, 32).dx, p(46, 32).dy)
      ..lineTo(p(62, 32).dx, p(62, 32).dy)
      ..arcToPoint(p(80, 50), radius: Radius.circular(18 * k))
      ..lineTo(p(80, 54).dx, p(80, 54).dy)
      ..arcToPoint(p(62, 72), radius: Radius.circular(18 * k))
      ..lineTo(p(50, 72).dx, p(50, 72).dy)
      ..lineTo(p(35, 83).dx, p(35, 83).dy)
      ..lineTo(p(38.5, 69.6).dx, p(38.5, 69.6).dy)
      ..arcToPoint(p(28, 54), radius: Radius.circular(18 * k))
      ..lineTo(p(28, 50).dx, p(28, 50).dy)
      ..arcToPoint(p(46, 32), radius: Radius.circular(18 * k))
      ..close();
    canvas.drawPath(bubble, Paint()..color = AppColors.spice);

    final Paint stroke = Paint()
      ..color = AppColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6 * k
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawPath(
        Path()
          ..moveTo(p(40.5, 51.5).dx, p(40.5, 51.5).dy)
          ..quadraticBezierTo(
            p(45.5, 45.5).dx,
            p(45.5, 45.5).dy,
            p(50.5, 51.5).dx,
            p(50.5, 51.5).dy,
          ),
        stroke,
      )
      ..drawCircle(p(63, 49.5), 4 * k, Paint()..color = AppColors.ink)
      ..drawPath(
        Path()
          ..moveTo(p(45, 60).dx, p(45, 60).dy)
          ..quadraticBezierTo(
            p(54, 66.5).dx,
            p(54, 66.5).dy,
            p(63, 59.5).dx,
            p(63, 59.5).dy,
          ),
        stroke,
      );
  }
}
