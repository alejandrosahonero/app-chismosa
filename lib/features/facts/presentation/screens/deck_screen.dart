import 'dart:async';

import 'package:aja/core/extensions/build_context_x.dart';
import 'package:aja/core/routing/app_routes.dart';
import 'package:aja/core/theme/app_spacing.dart';
import 'package:aja/core/utils/app_logger.dart';
import 'package:aja/core/widgets/adaptive_banner_ad.dart';
import 'package:aja/core/widgets/app_loader.dart';
import 'package:aja/core/widgets/base_screen.dart';
import 'package:aja/core/widgets/error_view.dart';
import 'package:aja/features/facts/data/fact_story_image.dart';
import 'package:aja/features/facts/domain/deck_item.dart';
import 'package:aja/features/facts/domain/fact.dart';
import 'package:aja/features/facts/presentation/providers/deck_controller.dart';
import 'package:aja/features/facts/presentation/providers/facts_providers.dart';
import 'package:aja/features/facts/presentation/providers/favorites_controller.dart';
import 'package:aja/features/facts/presentation/widgets/ad_deck_card.dart';
import 'package:aja/features/facts/presentation/widgets/deck_exhausted_view.dart';
import 'package:aja/features/facts/presentation/widgets/deck_swipe_progress.dart';
import 'package:aja/features/facts/presentation/widgets/fact_card.dart';
import 'package:aja/features/facts/presentation/widgets/swipe_deck.dart';
import 'package:aja/features/goals/domain/goals_state.dart';
import 'package:aja/features/goals/presentation/providers/goals_controller.dart';
import 'package:aja/features/goals/presentation/widgets/goal_celebration.dart';
import 'package:aja/features/goals/presentation/widgets/goal_ring_button.dart';
import 'package:aja/features/premium/presentation/widgets/premium_feature_dialog.dart';
import 'package:aja/l10n/generated/app_localizations.dart';
import 'package:aja/services/ads/ads_providers.dart';
import 'package:aja/services/review/review_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The whole app: a stack of cards you swipe through.
///
/// `showBanner: false` on purpose, and yet the deck does carry a banner. What
/// it refuses is `BaseScreen`'s *anchored* one: the body is a drag surface that
/// reaches the bottom of the screen, and a banner under a drag gesture is the
/// textbook accidental-click layout. The deck places its own inline instead —
/// above the cards, where a swipe never drags the finger across it. See
/// [_DeckBanner].
class DeckScreen extends ConsumerWidget {
  const DeckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DeckState> deck = ref.watch(deckControllerProvider);

    return BaseScreen(
      title: context.l10n.appTitle,
      showBanner: false,
      actions: <Widget>[
        const GoalRingButton(),
        IconButton(
          onPressed: () => context.goNamed(AppRoutes.favoritesName),
          icon: const Icon(Icons.bookmarks_outlined),
          tooltip: context.l10n.favoritesTitle,
        ),
        IconButton(
          onPressed: () => context.goNamed(AppRoutes.settingsName),
          icon: const Icon(Icons.settings_outlined),
          tooltip: context.l10n.settingsTitle,
        ),
      ],
      body: deck.when(
        loading: () => const AppLoader(),
        error: (Object error, StackTrace stackTrace) => ErrorView(
          message: context.l10n.deckLoadError,
          onRetry: () => ref.invalidate(factsProvider),
        ),
        data: (DeckState state) => _DeckBody(state: state),
      ),
    );
  }
}

/// Stateful only to own [_progress].
///
/// The drag notifier has to outlive the rebuilds the deck state causes, and it
/// is deliberately *not* a provider: it changes on every frame of every drag,
/// which is exactly the kind of traffic that does not belong in the app state.
class _DeckBody extends ConsumerStatefulWidget {
  const _DeckBody({required this.state});

  final DeckState state;

  @override
  ConsumerState<_DeckBody> createState() => _DeckBodyState();
}

class _DeckBodyState extends ConsumerState<_DeckBody> {
  /// Live drag, written by [SwipeDeck] and read by the badges over the card and
  /// the round buttons under it. Passing it down instead of lifting the drag
  /// into `setState` keeps the per-frame rebuild to the few widgets that
  /// actually animate.
  final ValueNotifier<DeckSwipeProgress> _progress =
      ValueNotifier<DeckSwipeProgress>(DeckSwipeProgress.idle);

  /// Rendering the image and opening the sheet takes a few hundred
  /// milliseconds. Without this, a second swipe inside that window queues a
  /// second share sheet behind the first one.
  bool _sharing = false;

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  DeckState get state => widget.state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        children: <Widget>[
          // Filter and banner sit above the deck and survive both states. The
          // exhausted screen is exactly where switching category is the most
          // useful thing the user can do, so the chips must not disappear with
          // the cards.
          const _CategoryChips(),
          const SizedBox(height: AppSpacing.sm),
          const _DeckBanner(),
          Expanded(
            child: state.isExhausted
                ? const DeckExhaustedView()
                : _deck(context),
          ),
        ],
      ),
    );
  }

  Widget _deck(BuildContext context) {
    final Set<String> favorites = ref.watch(favoritesProvider);

    return Column(
      children: <Widget>[
        Expanded(
          child: SwipeDeck(
            items: state.items,
            index: state.index,
            progress: _progress,
            onSwipeLeft: () => unawaited(_next(ref)),
            onSwipeRight: () => unawaited(_reveal(context, ref)),
            onSwipeUp: () => unawaited(_toggleFavorite(context, ref)),
            onSwipeDown: () => unawaited(_share(context, ref)),
            overlayBuilder:
                (BuildContext context, DeckSwipeProgress progress) =>
                    _SwipeBadges(progress: progress),
            builder: (BuildContext context, DeckItem item, int depth) {
              final bool isTop = depth == 0;
              return switch (item) {
                FactItem(:final Fact fact) => FactCard(
                  fact: fact,
                  revealed: isTop && state.revealed,
                  favorited: favorites.contains(fact.id),
                  onTap: isTop ? () => unawaited(_reveal(context, ref)) : null,
                ),
                // Depth and not `isTop`: the ad card fetches its creative one
                // place early so it is not still loading when it arrives.
                AdItem() => AdDeckCard(depth: depth),
              };
            },
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _DeckControls(
          state: state,
          progress: _progress,
          favorited: switch (state.current) {
            FactItem(:final Fact fact) => favorites.contains(fact.id),
            _ => false,
          },
          onNext: () => unawaited(_next(ref)),
          onReveal: () => unawaited(_reveal(context, ref)),
          onFavorite: () => unawaited(_toggleFavorite(context, ref)),
          onShare: () => unawaited(_share(context, ref)),
        ),
      ],
    );
  }

  /// Swipe up / bookmark button.
  ///
  /// The entitlement is checked here and not in [FavoritesController] because
  /// the "no" branch has to open the paywall, which needs a context. A locked
  /// user still gets to make the gesture: that attempt is the value moment the
  /// upsell hangs off.
  Future<void> _toggleFavorite(BuildContext context, WidgetRef ref) async {
    final DeckItem? current = state.current;
    if (current is! FactItem) return;

    if (!ref.read(canUseFavoritesProvider)) {
      await showPremiumFeatureDialog(context);
      return;
    }

    await ref.read(favoritesProvider.notifier).toggle(current.fact.id);
  }

  /// Swipe down / share button.
  ///
  /// Free for everybody, unlike favourites. A shared card is the cheapest
  /// install this app will ever get, so putting it behind the paywall would be
  /// charging for the marketing.
  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final DeckItem? current = state.current;
    if (current is! FactItem || _sharing) return;
    _sharing = true;

    // Everything the image needs is resolved before the first await: the
    // renderer runs without a context, and one looked up afterwards is one that
    // may already be gone.
    final Fact fact = current.fact;
    final AppLocalizations l10n = context.l10n;
    final String language = Localizations.localeOf(context).languageCode;
    final FactStoryLabels labels = FactStoryLabels(
      appName: l10n.appTitle,
      tagline: l10n.deckShareTagline,
      category: fact.category.label(context),
      callToAction: l10n.deckShareCta,
    );

    try {
      await ref
          .read(factShareServiceProvider)
          .shareQuestion(
            fact: fact,
            language: language,
            labels: labels,
            message: l10n.deckShareMessage(fact.question.resolve(language)),
          );
    } on Object catch (error, stackTrace) {
      // Never rethrown: a share sheet that will not open is an annoyance, not
      // a reason to take the deck down.
      AppLogger.error(
        'Sharing a fact failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (context.mounted) context.showSnack(l10n.deckShareError);
    } finally {
      _sharing = false;
    }
  }

  /// Flipping a card to read the answer is the value moment of this app, so it
  /// is the only place two things are counted from.
  ///
  /// The review prompt: the service's own guards (5 successes, 3 days, 120
  /// days) decide whether anything is actually shown.
  ///
  /// The daily goal: this — not swiping the card away — is what "learning a
  /// fact" means. Counting dismissals instead would fill the goal with
  /// everything a fast scroller skipped past without reading.
  Future<void> _reveal(BuildContext context, WidgetRef ref) async {
    final bool wasHidden = !state.revealed;
    ref.read(deckControllerProvider.notifier).toggleReveal();

    // Hiding the answer again is not a second success.
    final DeckItem? current = state.current;
    if (!wasHidden || current is! FactItem) return;

    unawaited(ref.read(reviewServiceProvider).requestReviewAfterSuccess());

    final GoalEvent event = await ref
        .read(goalsControllerProvider.notifier)
        .registerLearned(current.fact.id);

    if (!context.mounted) return;
    await showGoalEvent(context, event);
  }

  /// One swiped card = one "value action" for the interstitial pacing. The
  /// service still enforces the 3 minute floor, so a fast reader does not get
  /// an ad every nine cards.
  Future<void> _next(WidgetRef ref) async {
    final DeckItem? dismissed = await ref
        .read(deckControllerProvider.notifier)
        .next();

    if (dismissed is FactItem) {
      await ref
          .read(adsServiceProvider)
          .registerActionAndMaybeShowInterstitial();
    }
  }
}

/// Palette of the four actions, in one place.
///
/// The badge over the card and the button under it have to be the same colour
/// for the association to work, and a colour defined twice is a colour that
/// drifts.
extension on DeckSwipeDirection {
  Color color(BuildContext context) => switch (this) {
    DeckSwipeDirection.left => context.colors.onSurfaceVariant,
    DeckSwipeDirection.right => context.colors.primary,
    DeckSwipeDirection.up => context.colors.tertiary,
    DeckSwipeDirection.down => context.colors.secondary,
    DeckSwipeDirection.none => context.colors.outline,
  };
}

class _SwipeBadges extends StatelessWidget {
  const _SwipeBadges({required this.progress});

  final DeckSwipeProgress progress;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _SwipeBadge(
          icon: Icons.close_rounded,
          direction: DeckSwipeDirection.left,
          alignment: Alignment.topRight,
          amount: progress.amountFor(DeckSwipeDirection.left),
        ),
        _SwipeBadge(
          icon: Icons.flip_to_back,
          direction: DeckSwipeDirection.right,
          alignment: Alignment.topLeft,
          amount: progress.amountFor(DeckSwipeDirection.right),
        ),
        _SwipeBadge(
          icon: Icons.bookmark_add_outlined,
          direction: DeckSwipeDirection.up,
          alignment: Alignment.bottomCenter,
          amount: progress.amountFor(DeckSwipeDirection.up),
        ),
        _SwipeBadge(
          icon: Icons.ios_share,
          direction: DeckSwipeDirection.down,
          alignment: Alignment.topCenter,
          amount: progress.amountFor(DeckSwipeDirection.down),
        ),
      ],
    );
  }
}

/// One badge: a filled disc that fades and swells with the drag.
class _SwipeBadge extends StatelessWidget {
  const _SwipeBadge({
    required this.icon,
    required this.direction,
    required this.alignment,
    required this.amount,
  });

  final IconData icon;
  final DeckSwipeDirection direction;
  final AlignmentGeometry alignment;

  /// 0 at rest, 1 at the commit threshold.
  final double amount;

  @override
  Widget build(BuildContext context) {
    if (amount <= 0) return const SizedBox.shrink();

    final double t = Curves.easeOut.transform(amount.clamp(0.0, 1.0));
    final Color color = direction.color(context);

    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Opacity(
          // Faster than the scale so the badge is legible well before the
          // threshold: the point is to tell the user what will happen while
          // there is still time to change their mind.
          opacity: (t * 1.6).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.65 + 0.45 * t,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                // A ring in the deck's surface colour, so the disc stays
                // readable over either face of the card.
                border: Border.all(
                  color: context.colors.surfaceContainerHigh,
                  width: 3,
                ),
              ),
              child: Icon(
                icon,
                size: 30,
                color:
                    ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Category filter as a scrollable row of chips.
///
/// Replaces the popup menu that used to live in the app bar. Chips cost
/// vertical space that would otherwise belong to the card, which is why the
/// row is as short as a touch target allows and why the deck sits in an
/// [Expanded] that simply gives way. What they buy is discoverability: the
/// categories are now visible without opening anything, and switching one is a
/// single tap instead of three.
class _CategoryChips extends ConsumerWidget {
  const _CategoryChips();

  /// Comfortably over the 48dp touch target once the chip's own tap padding is
  /// counted, and small enough that the card keeps the screen.
  static const double _height = 40;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FactCategory? selected = ref.watch(categoryFilterProvider);

    return SizedBox(
      height: _height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        // "All" first, then one chip per category.
        itemCount: FactCategory.values.length + 1,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: AppSpacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final FactCategory? category = index == 0
              ? null
              : FactCategory.values[index - 1];

          return _CategoryChip(
            label: category?.label(context) ?? context.l10n.deckCategoryAll,
            selected: category == selected,
            onSelected: () =>
                ref.read(categoryFilterProvider.notifier).select(category),
          );
        },
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      // The tick would push the label sideways on every tap, so selection is
      // carried by the fill colour alone.
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      labelStyle: context.texts.labelLarge?.copyWith(
        color: selected ? context.colors.onSecondaryContainer : null,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      ),
      // Re-tapping the selected chip must not clear the filter: on a filter
      // row, a tap means "show me this one".
      onSelected: (bool _) => onSelected(),
    );
  }
}

/// Banner slot between the filter and the deck.
///
/// Above the cards on purpose. An anchored banner under a full-screen drag
/// surface is the textbook accidental-click layout, and this deck is dragged in
/// four directions; here the finger never travels over the ad on its way out of
/// a swipe. It also renders nothing at all — no reserved strip — for premium
/// users and whenever no creative loads, so the card gets the space back
/// instead of staring at a grey box.
class _DeckBanner extends StatelessWidget {
  const _DeckBanner();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: AdaptiveBannerAd(
        anchored: false,
        // Inside the banner, not around it: an empty slot must cost the deck
        // nothing at all, gap included.
        padding: EdgeInsets.only(bottom: AppSpacing.sm),
      ),
    );
  }
}

/// The three swipes mirrored as round buttons, laid out the way a card deck
/// trains you to expect: discard on the left, save in the middle, reveal on the
/// right — each control on the side its gesture throws the card towards, and
/// wearing the same icon as the badge that fades in mid-drag.
///
/// Each button also grows with its own gesture, so the drag names the action it
/// is about to fire without the user having to look away from the card.
///
/// Not decoration: a drag-only interface is unusable with a screen reader or
/// switch access, and Play flags that in the accessibility scan. The tooltip is
/// what gets announced, so every button carries one.
class _DeckControls extends StatelessWidget {
  const _DeckControls({
    required this.state,
    required this.progress,
    required this.favorited,
    required this.onNext,
    required this.onReveal,
    required this.onFavorite,
    required this.onShare,
  });

  final DeckState state;
  final ValueNotifier<DeckSwipeProgress> progress;
  final bool favorited;
  final VoidCallback onNext;
  final VoidCallback onReveal;
  final VoidCallback onFavorite;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final bool isFact = state.current is FactItem;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _DeckButton(
          icon: Icons.close_rounded,
          direction: DeckSwipeDirection.left,
          progress: progress,
          tooltip: context.l10n.deckNext,
          onPressed: onNext,
        ),
        const SizedBox(width: AppSpacing.md),
        // Smaller and in the middle, where the upward swipe points. Never
        // disabled for a locked user: tapping it is how they find out the
        // feature exists and what unlocks it.
        _DeckButton(
          icon: favorited ? Icons.bookmark : Icons.bookmark_add_outlined,
          direction: DeckSwipeDirection.up,
          progress: progress,
          tooltip: favorited
              ? context.l10n.favoritesRemove
              : context.l10n.favoritesAdd,
          onPressed: isFact ? onFavorite : null,
          diameter: _DeckButton.small,
        ),
        const SizedBox(width: AppSpacing.md),
        // The other vertical gesture, next to the one it shares an axis with.
        _DeckButton(
          icon: Icons.ios_share,
          direction: DeckSwipeDirection.down,
          progress: progress,
          tooltip: context.l10n.deckShare,
          onPressed: isFact ? onShare : null,
          diameter: _DeckButton.small,
        ),
        const SizedBox(width: AppSpacing.md),
        _DeckButton(
          icon: state.revealed ? Icons.flip_to_front : Icons.flip_to_back,
          direction: DeckSwipeDirection.right,
          progress: progress,
          tooltip: state.revealed
              ? context.l10n.deckHideAnswer
              : context.l10n.deckShowAnswer,
          onPressed: isFact ? onReveal : null,
        ),
      ],
    );
  }
}

/// One round control: a tinted ring over the surface colour, with the icon in
/// the same tint.
///
/// It listens to [progress] on its own instead of taking a plain number, so a
/// drag repaints three small buttons and nothing else on the screen.
class _DeckButton extends StatelessWidget {
  const _DeckButton({
    required this.icon,
    required this.direction,
    required this.progress,
    required this.tooltip,
    required this.onPressed,
    this.diameter = large,
  });

  /// Comfortably past the 48dp minimum touch target on both sizes.
  static const double large = 64;
  static const double small = 52;

  /// How much bigger the button gets at the commit threshold. Enough to be
  /// unmistakable, small enough that the three buttons never collide.
  static const double maxZoom = 0.4;

  final IconData icon;

  /// The gesture this button answers to.
  final DeckSwipeDirection direction;

  final ValueNotifier<DeckSwipeProgress> progress;
  final String tooltip;

  /// Null disables the button, which only happens while the ad card is on top.
  final VoidCallback? onPressed;

  final double diameter;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;
    final Color color = direction.color(context);

    return Tooltip(
      message: tooltip,
      child: ValueListenableBuilder<DeckSwipeProgress>(
        valueListenable: progress,
        builder: (BuildContext context, DeckSwipeProgress value, Widget? _) {
          // A disabled button belongs to a card that cannot be acted on, so it
          // must not answer the drag either.
          final double t = enabled
              ? Curves.easeOut.transform(value.amountFor(direction))
              : 0;

          // Faded rather than greyed: the button keeps its identity while it
          // waits. Under the finger it does the opposite, filling in with its
          // own tint until it reads as pressed.
          final Color tint = enabled ? color : color.withValues(alpha: 0.3);

          return Transform.scale(
            scale: 1 + maxZoom * t,
            child: SizedBox.square(
              dimension: diameter,
              child: Material(
                color: Color.lerp(
                  context.colors.surface,
                  tint.withValues(alpha: 0.2),
                  t,
                ),
                elevation: enabled ? 2 + 6 * t : 0,
                shadowColor: context.colors.shadow,
                shape: CircleBorder(
                  side: BorderSide(
                    color: tint.withValues(alpha: 0.4 + 0.6 * t),
                    width: 1 + t,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPressed,
                  child: Center(
                    child: Icon(icon, color: tint, size: diameter * 0.42),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
