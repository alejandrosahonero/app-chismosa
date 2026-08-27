import 'dart:math' as math;

import 'package:aja/core/extensions/build_context_x.dart';
import 'package:aja/core/theme/app_spacing.dart';
import 'package:aja/features/facts/domain/fact.dart';
import 'package:aja/features/facts/presentation/widgets/deck_card_shell.dart';
import 'package:aja/features/facts/presentation/widgets/fact_source_link.dart';
import 'package:flutter/material.dart';

/// Localized name of a category, for the chip on the front of the card.
extension FactCategoryX on FactCategory {
  String label(BuildContext context) => switch (this) {
    FactCategory.body => context.l10n.categoryBody,
    FactCategory.language => context.l10n.categoryLanguage,
    FactCategory.history => context.l10n.categoryHistory,
    FactCategory.science => context.l10n.categoryScience,
  };
}

/// A question on the front, the answer and its source on the back.
///
/// The flip is driven by [revealed], which lives in the deck controller: the
/// card animates towards whatever the state says, so a swipe, a tap and a
/// button press all take the same path.
class FactCard extends StatefulWidget {
  const FactCard({
    required this.fact,
    required this.revealed,
    super.key,
    this.favorited = false,
    this.onTap,
  });

  final Fact fact;
  final bool revealed;

  /// Painted on both faces: the user has to be able to tell a card is saved
  /// without flipping it back.
  final bool favorited;

  final VoidCallback? onTap;

  @override
  State<FactCard> createState() => _FactCardState();
}

class _FactCardState extends State<FactCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: widget.revealed ? 1 : 0,
  );

  late final Animation<double> _turn = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );

  @override
  void didUpdateWidget(FactCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.revealed == oldWidget.revealed) return;
    if (widget.revealed) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String language = Localizations.localeOf(context).languageCode;

    // The card repaints ~60 times per flip while the rest of the deck is
    // static; isolating it keeps the cards underneath out of the repaint.
    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _turn,
          builder: (BuildContext context, Widget? child) {
            final double angle = _turn.value * math.pi;
            final bool showBack = angle > math.pi / 2;

            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                // Perspective, otherwise the flip reads as a flat squash.
                ..setEntry(3, 2, 0.0012)
                ..rotateY(angle),
              child: showBack
                  ? Transform(
                      alignment: Alignment.center,
                      // Un-mirror the back, which is otherwise painted
                      // reversed by the parent rotation.
                      transform: Matrix4.identity()..rotateY(math.pi),
                      child: _CardBack(
                        fact: widget.fact,
                        language: language,
                        favorited: widget.favorited,
                      ),
                    )
                  : _CardFront(
                      fact: widget.fact,
                      language: language,
                      favorited: widget.favorited,
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _CardFront extends StatelessWidget {
  const _CardFront({
    required this.fact,
    required this.language,
    required this.favorited,
  });

  final Fact fact;
  final String language;
  final bool favorited;

  @override
  Widget build(BuildContext context) {
    return DeckCardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _CategoryChip(category: fact.category),
              const Spacer(),
              if (favorited) _FavoriteMark(color: context.colors.primary),
            ],
          ),
          const Spacer(),
          Text(
            fact.question.resolve(language),
            style: context.texts.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          const Spacer(flex: 2),
          _SwipeLegend(
            text: context.l10n.deckHintReveal,
            icon: Icons.swipe_right_alt,
          ),
        ],
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  const _CardBack({
    required this.fact,
    required this.language,
    required this.favorited,
  });

  final Fact fact;
  final String language;
  final bool favorited;

  @override
  Widget build(BuildContext context) {
    return DeckCardShell(
      color: context.colors.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  context.l10n.deckAnswerLabel,
                  style: context.texts.labelLarge?.copyWith(
                    color: context.colors.onPrimaryContainer.withValues(
                      alpha: 0.7,
                    ),
                  ),
                ),
              ),
              if (favorited)
                _FavoriteMark(color: context.colors.onPrimaryContainer),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // The detail text is the only part that can overflow on a small
          // screen with a large font scale, so it is the only scrollable one.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    fact.answer.resolve(language),
                    style: context.texts.titleLarge?.copyWith(
                      color: context.colors.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    fact.detail.resolve(language),
                    style: context.texts.bodyMedium?.copyWith(
                      color: context.colors.onPrimaryContainer,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FactSourceLink(
            source: fact.source,
            url: fact.sourceUrl,
            color: context.colors.onPrimaryContainer.withValues(alpha: 0.7),
          ),
          const SizedBox(height: AppSpacing.sm),
          _SwipeLegend(
            text: context.l10n.deckHintNext,
            icon: Icons.swipe_left_alt,
            color: context.colors.onPrimaryContainer.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }
}

/// Marks a saved card. Carries a semantic label because the icon alone says
/// nothing to a screen reader.
class _FavoriteMark extends StatelessWidget {
  const _FavoriteMark({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.l10n.favoritesSaved,
      child: Icon(Icons.bookmark, color: color),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category});

  final FactCategory category;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          category.label(context),
          style: context.texts.labelMedium?.copyWith(
            color: context.colors.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

class _SwipeLegend extends StatelessWidget {
  const _SwipeLegend({required this.text, required this.icon, this.color});

  final String text;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color resolved = color ?? context.colors.onSurfaceVariant;

    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: resolved),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: context.texts.labelMedium?.copyWith(color: resolved),
          ),
        ),
      ],
    );
  }
}
