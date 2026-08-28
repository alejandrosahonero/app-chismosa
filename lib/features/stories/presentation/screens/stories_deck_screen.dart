import 'dart:async';

import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/routing/app_routes.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
import 'package:chismosa/core/widgets/adaptive_banner_ad.dart';
import 'package:chismosa/core/widgets/app_loader.dart';
import 'package:chismosa/core/widgets/base_screen.dart';
import 'package:chismosa/core/widgets/deck/ad_deck_card.dart';
import 'package:chismosa/core/widgets/deck/deck_card.dart';
import 'package:chismosa/core/widgets/deck/deck_controls.dart';
import 'package:chismosa/core/widgets/deck/deck_swipe_progress.dart';
import 'package:chismosa/core/widgets/deck/deck_thresholds.dart';
import 'package:chismosa/core/widgets/deck/swipe_deck.dart';
import 'package:chismosa/core/widgets/empty_state.dart';
import 'package:chismosa/core/widgets/error_view.dart';
import 'package:chismosa/features/stories/domain/story.dart';
import 'package:chismosa/features/stories/domain/story_deck.dart';
import 'package:chismosa/features/stories/presentation/providers/stories_deck_controller.dart';
import 'package:chismosa/features/stories/presentation/widgets/story_card_view.dart';
import 'package:chismosa/features/stories/presentation/widgets/story_filters.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:chismosa/services/ads/ads_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Gesture costs of the stories deck.
///
/// Three of the four directions consume the card, so they are cheap: passing on
/// somebody's story should take no effort at all. Up is the odd one out — it
/// opens the thread on top of the app — so it is the only direction a bare
/// flick cannot commit on its own.
const DeckThresholds _storyThresholds = DeckThresholds(
  left: 0.28,
  right: 0.28,
  up: 0.16,
  down: 0.22,
  requireTravel: <DeckSwipeDirection>{DeckSwipeDirection.up},
);

/// The deck. It is the app.
class StoriesDeckScreen extends ConsumerStatefulWidget {
  const StoriesDeckScreen({super.key});

  @override
  ConsumerState<StoriesDeckScreen> createState() => _StoriesDeckScreenState();
}

class _StoriesDeckScreenState extends ConsumerState<StoriesDeckScreen> {
  /// Live drag, written by [SwipeDeck] and read by the badges over the card and
  /// the buttons under it.
  ///
  /// A notifier rather than `setState` on purpose: this changes on every frame
  /// of every drag, and only the buttons should repaint — not the deck, and not
  /// the filters above it.
  final ValueNotifier<DeckSwipeProgress> _progress =
      ValueNotifier<DeckSwipeProgress>(DeckSwipeProgress.idle);

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<StoriesDeckState> deck = ref.watch(
      storiesDeckControllerProvider,
    );

    return BaseScreen(
      title: context.l10n.appTitle,
      // The banner is placed by hand inside the layout, above the cards. See
      // [_body].
      showBanner: false,
      actions: <Widget>[
        IconButton(
          onPressed: () => context.goNamed(AppRoutes.settingsName),
          icon: const Icon(Icons.settings_outlined),
          tooltip: context.l10n.settingsTitle,
        ),
      ],
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.goNamed(AppRoutes.composeName),
        tooltip: context.l10n.composeTitle,
        child: const Icon(Icons.edit_outlined),
      ),
      body: deck.when(
        loading: () => const AppLoader(),
        error: (Object error, StackTrace stack) => ErrorView(
          message: context.l10n.storiesOfflineBody,
          onRetry: () => ref.invalidate(storiesDeckControllerProvider),
        ),
        data: _body,
      ),
    );
  }

  Widget _body(StoriesDeckState state) {
    return Column(
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: StoryFilters(),
        ),
        // Above the cards, never below them. The deck is dragged in four
        // directions, and a banner pinned to the bottom edge under that gesture
        // is the textbook accidental click. Up here the finger never lands on
        // it coming out of a swipe.
        const AdaptiveBannerAd(anchored: false),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: state.isExhausted
                ? _Exhausted(onRestart: _restart)
                : state.isWaiting
                ? const AppLoader()
                : _deck(state),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Controls(state: state, progress: _progress, onAction: _run),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }

  Widget _deck(StoriesDeckState state) {
    return SwipeDeck(
      items: state.items,
      index: state.index,
      progress: _progress,
      thresholds: _storyThresholds,
      // Everything but "open the thread" consumes the card. Down is a second
      // way to pass: the reader who is scrolling fast should not have to aim.
      dismissOn: const <DeckSwipeDirection>{
        DeckSwipeDirection.left,
        DeckSwipeDirection.right,
        DeckSwipeDirection.down,
      },
      onSwipe: _run,
      overlayBuilder: (BuildContext context, DeckSwipeProgress progress) =>
          _Badges(progress: progress),
      builder: (BuildContext context, DeckCard card, int depth) =>
          switch (card as StoryDeckItem) {
            StoryCard(:final Story story) => StoryCardView(story: story),
            // Depth and not "is this the top one": the ad slot fetches its
            // creative one place early so it is not still loading when it
            // arrives.
            StoryAdCard() => AdDeckCard(depth: depth),
          },
    );
  }

  /// Single entry point for every gesture and every button, so the two can
  /// never drift apart.
  void _run(DeckSwipeDirection direction) {
    switch (direction) {
      case DeckSwipeDirection.left:
      case DeckSwipeDirection.down:
        unawaited(_pass());
      case DeckSwipeDirection.right:
        unawaited(_like());
      case DeckSwipeDirection.up:
        unawaited(_openThread());
      case DeckSwipeDirection.none:
        break;
    }
  }

  Future<void> _pass() async {
    await ref.read(storiesDeckControllerProvider.notifier).pass();
    _countCardForAds();
  }

  Future<void> _like() async {
    await ref.read(storiesDeckControllerProvider.notifier).like();
    _countCardForAds();
  }

  /// Up swipe: join the thread.
  ///
  /// The thread itself is the next feature to land; until then this confirms
  /// the join, which is the part that has to be right — the membership is what
  /// creates the alias and puts the conversation in the reader's history.
  Future<void> _openThread() async {
    final StoriesDeckController controller = ref.read(
      storiesDeckControllerProvider.notifier,
    );
    try {
      final Story? story = await controller.joinTopThread();
      if (story == null || !mounted) return;
      context.showSnack(context.l10n.storiesJoinedThread);
    } on Object {
      if (!mounted) return;
      context.showSnack(context.l10n.storiesOfflineBody);
    }
  }

  Future<void> _restart() =>
      ref.read(storiesDeckControllerProvider.notifier).restart();

  /// One consumed card is one "value action" for the interstitial pacing.
  ///
  /// The service decides whether anything actually shows: both the action count
  /// and the three minute floor have to be satisfied.
  void _countCardForAds() {
    if (!ref.read(adsInitializedProvider)) return;
    unawaited(
      ref.read(adsServiceProvider).registerActionAndMaybeShowInterstitial(),
    );
  }
}

class _Exhausted extends StatelessWidget {
  const _Exhausted({required this.onRestart});

  final Future<void> Function() onRestart;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = context.l10n;

    return EmptyState(
      icon: Icons.forum_outlined,
      title: l10n.storiesEmptyTitle,
      message: l10n.storiesEmptyBody,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Writing beats re-reading: a reader who has run out is the reader
          // most likely to have something of their own to say.
          FilledButton.icon(
            onPressed: () => context.goNamed(AppRoutes.composeName),
            icon: const Icon(Icons.edit_outlined),
            label: Text(l10n.storiesEmptyWrite),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: () => unawaited(onRestart()),
            child: Text(l10n.storiesEmptyRestart),
          ),
        ],
      ),
    );
  }
}

class _Badges extends StatelessWidget {
  const _Badges({required this.progress});

  final DeckSwipeProgress progress;

  @override
  Widget build(BuildContext context) {
    // Each badge sits on the edge **opposite** its gesture: the edge the card
    // is heading for leaves the screen and would take the icon with it exactly
    // as it confirms what is about to happen.
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        DeckSwipeBadge(
          icon: Icons.close_rounded,
          direction: DeckSwipeDirection.left,
          alignment: Alignment.topRight,
          amount: progress.amountFor(DeckSwipeDirection.left),
        ),
        DeckSwipeBadge(
          icon: Icons.favorite,
          direction: DeckSwipeDirection.right,
          alignment: Alignment.topLeft,
          amount: progress.amountFor(DeckSwipeDirection.right),
        ),
        DeckSwipeBadge(
          icon: Icons.forum,
          direction: DeckSwipeDirection.up,
          alignment: Alignment.bottomCenter,
          amount: progress.amountFor(DeckSwipeDirection.up),
        ),
        DeckSwipeBadge(
          icon: Icons.keyboard_double_arrow_down,
          direction: DeckSwipeDirection.down,
          alignment: Alignment.topCenter,
          amount: progress.amountFor(DeckSwipeDirection.down),
        ),
      ],
    );
  }
}

/// The buttons under the deck.
///
/// Not decorative: a drag-only surface is unusable with a screen reader and is
/// penalised by Play's accessibility scan. Down has no button of its own — it
/// is a second way to do what "pass" already does.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.state,
    required this.progress,
    required this.onAction,
  });

  final StoriesDeckState state;
  final ValueNotifier<DeckSwipeProgress> progress;
  final void Function(DeckSwipeDirection direction) onAction;

  @override
  Widget build(BuildContext context) {
    final bool isStory = state.current is StoryCard;
    final AppLocalizations l10n = context.l10n;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        DeckActionButton(
          icon: Icons.close_rounded,
          direction: DeckSwipeDirection.left,
          progress: progress,
          tooltip: l10n.storiesPass,
          onPressed: state.current == null
              ? null
              : () => onAction(DeckSwipeDirection.left),
        ),
        const SizedBox(width: AppSpacing.md),
        // Smaller and in the middle, where the upward swipe points.
        DeckActionButton(
          icon: Icons.forum_outlined,
          direction: DeckSwipeDirection.up,
          progress: progress,
          tooltip: l10n.storiesThread,
          onPressed: isStory ? () => onAction(DeckSwipeDirection.up) : null,
          diameter: DeckActionButton.small,
        ),
        const SizedBox(width: AppSpacing.md),
        DeckActionButton(
          icon: Icons.favorite_border,
          direction: DeckSwipeDirection.right,
          progress: progress,
          tooltip: l10n.storiesLike,
          onPressed: isStory ? () => onAction(DeckSwipeDirection.right) : null,
        ),
      ],
    );
  }
}
