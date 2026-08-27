import 'package:aja/core/extensions/build_context_x.dart';
import 'package:aja/core/theme/app_spacing.dart';
import 'package:aja/core/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The "Fuente: …" line under an answer, tappable when the entry carries a
/// permanent link.
///
/// Every fact in the catalogue is checked against a real page before it ships,
/// so the citation is not decoration: the user gets to go and read it. That is
/// also the honest way to run a curiosities app — a claim nobody can check is
/// a claim nobody should believe.
///
/// Degrades to plain text when [url] is empty rather than rendering a dead
/// link. A remotely published entry can arrive without one.
class FactSourceLink extends StatelessWidget {
  const FactSourceLink({
    required this.source,
    required this.url,
    super.key,
    this.color,
  });

  final String source;

  /// Empty means "no link", not "broken link".
  final String url;

  /// The card back and the favourites list sit on different surfaces, so the
  /// tint is passed in rather than looked up.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color resolved = color ?? context.colors.onSurfaceVariant;
    final String label = context.l10n.deckSource(source);
    final TextStyle? style = context.texts.labelSmall?.copyWith(
      color: resolved,
    );

    if (url.isEmpty) return Text(label, style: style);

    return Semantics(
      link: true,
      child: InkWell(
        // The card back is itself a tap target that flips the card. The inner
        // gesture wins the arena, so opening the source never flips it back.
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Flexible(
                child: Text(
                  label,
                  style: style?.copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: resolved,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              // Underline alone reads as emphasis on a small label; the icon is
              // what says "this leaves the app".
              Icon(Icons.open_in_new, size: 14, color: resolved),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final String message = context.l10n.deckSourceOpenError;

    try {
      final bool opened = await launchUrl(
        Uri.parse(url),
        // The browser, not a webview: the user is leaving to read a source and
        // should land somewhere they can check the address bar.
        mode: LaunchMode.externalApplication,
      );
      if (opened || !context.mounted) return;
    } on Object catch (error, stackTrace) {
      // Never rethrown: a source that will not open is an annoyance, not a
      // reason to take the deck down.
      AppLogger.error(
        'Opening a fact source failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!context.mounted) return;
    }

    context.showSnack(message);
  }
}
