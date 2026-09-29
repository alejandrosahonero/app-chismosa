import 'dart:async';

import 'package:chismosa/core/config/app_config.dart';
import 'package:chismosa/core/config/links_config.dart';
import 'package:chismosa/core/extensions/build_context_x.dart';
import 'package:chismosa/core/routing/app_routes.dart';
import 'package:chismosa/core/theme/app_spacing.dart';
import 'package:chismosa/core/utils/shake_detector.dart';
import 'package:chismosa/core/widgets/adaptive_banner_ad.dart';
import 'package:chismosa/core/widgets/app_drawer.dart';
import 'package:chismosa/core/widgets/app_loader.dart';
import 'package:chismosa/core/widgets/base_screen.dart';
import 'package:chismosa/core/widgets/confirm_dialog.dart';
import 'package:chismosa/core/widgets/deck/ad_deck_card.dart';
import 'package:chismosa/core/widgets/deck/deck_card.dart';
import 'package:chismosa/core/widgets/deck/deck_controls.dart';
import 'package:chismosa/core/widgets/deck/deck_swipe_progress.dart';
import 'package:chismosa/core/widgets/deck/deck_thresholds.dart';
import 'package:chismosa/core/widgets/deck/swipe_deck.dart';
import 'package:chismosa/core/widgets/empty_state.dart';
import 'package:chismosa/core/widgets/error_view.dart';
import 'package:chismosa/core/widgets/report_reason_sheet.dart';
import 'package:chismosa/features/stories/domain/feed_query.dart';
import 'package:chismosa/features/stories/domain/story.dart';
import 'package:chismosa/features/stories/domain/story_deck.dart';
import 'package:chismosa/features/stories/presentation/providers/stories_deck_controller.dart';
import 'package:chismosa/features/stories/presentation/providers/stories_providers.dart';
import 'package:chismosa/features/stories/presentation/widgets/story_card_view.dart';
import 'package:chismosa/features/stories/presentation/widgets/story_filters.dart';
import 'package:chismosa/features/threads/presentation/providers/thread_controller.dart';
import 'package:chismosa/features/threads/presentation/widgets/thread_panel.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:chismosa/services/ads/ads_providers.dart';
import 'package:chismosa/services/review/review_providers.dart';
import 'package:chismosa/services/storage/key_value_store.dart';
import 'package:chismosa/services/storage/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Gesture costs of the stories deck.
///
/// Left and right consume the card, so they are cheap: passing on somebody's
/// story should take no effort at all. Up (the thread) and down (share) open
/// something over the app, so a bare flick cannot commit either: they need the
/// finger to travel. Down is the longest of all — it hands the story to
/// another app, and a thumb slipping must never do that.
const DeckThresholds _storyThresholds = DeckThresholds(
  left: 0.28,
  right: 0.28,
  up: 0.16,
  down: 0.26,
  requireTravel: <DeckSwipeDirection>{
    DeckSwipeDirection.up,
    DeckSwipeDirection.down,
  },
);

/// The deck. It is the app.
class StoriesDeckScreen extends ConsumerStatefulWidget {
  const StoriesDeckScreen({super.key});

  @override
  ConsumerState<StoriesDeckScreen> createState() => _StoriesDeckScreenState();
}

class _StoriesDeckScreenState extends ConsumerState<StoriesDeckScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Set once the reader has been told a shake brings a card back.
  static const String _undoHintKey = 'deck_undo_hint_shown';

  /// Fraction of the sheet an upward drag alone can reveal.
  ///
  /// Enough that the conversation behind the gesture is recognisable while
  /// there is still time to change one's mind, and not so much that a drag
  /// that was going to be cancelled covers the card it came from.
  static const double _peek = 0.45;

  /// Live drag, written by [SwipeDeck] and read by the badges over the card and
  /// the buttons under it.
  ///
  /// A notifier rather than `setState` on purpose: this changes on every frame
  /// of every drag, and only the buttons should repaint — not the deck, and not
  /// the filters above it.
  final ValueNotifier<DeckSwipeProgress> _progress =
      ValueNotifier<DeckSwipeProgress>(DeckSwipeProgress.idle);

  /// How far the thread sheet is out: 0 hidden, 1 fully open.
  ///
  /// The upward drag writes straight into this while the finger is down, and
  /// the controller takes over from wherever the drag left it once the gesture
  /// commits. That hand-off is what makes the sheet one continuous movement
  /// rather than a gesture followed by an animation starting from scratch.
  late final AnimationController _sheet = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 200),
  );

  /// Set from the moment the gesture commits until the sheet is back down.
  /// While it holds, the drag no longer drives [_sheet]: the conversation owns
  /// the screen.
  bool _threadOpen = false;

  /// Shake to bring back the last card swiped away. Only listens while the app
  /// is in the foreground.
  late final ShakeDetector _shake = ShakeDetector(onShake: _undo);

  @override
  void initState() {
    super.initState();
    _progress.addListener(_followDrag);
    WidgetsBinding.instance.addObserver(this);
    _shake.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _shake.start();
    } else {
      _shake.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shake.stop();
    _progress.removeListener(_followDrag);
    _progress.dispose();
    _sheet.dispose();
    super.dispose();
  }

  /// Lets the sheet peek out while the finger drags upwards.
  ///
  /// Writing to the controller's value rather than calling `setState` keeps
  /// this off the deck: it runs on every frame of every upward drag, and the
  /// cards must not rebuild for it.
  void _followDrag() {
    if (_threadOpen || _sheet.isAnimating) return;
    _sheet.value = _progress.value.amountFor(DeckSwipeDirection.up) * _peek;
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<StoriesDeckState> deck = ref.watch(
      storiesDeckControllerProvider,
    );

    // Inside a group the title says so: the filter row that used to name the
    // deck is gone, and the groups screen is how to leave.
    final String? groupId = ref.watch(
      feedQueryProvider.select((FeedQuery q) => q.groupId),
    );

    return BaseScreen(
      title: groupId == null
          ? context.l10n.appTitle
          : deckName(ref, groupId) ?? context.l10n.groupsTitle,
      actions: <Widget>[
        IconButton(
          onPressed: () => context.pushNamed(AppRoutes.likedName),
          icon: const Icon(Icons.favorite_border),
          tooltip: context.l10n.likedTitle,
        ),
        const StoryFiltersButton(),
      ],
      // The banner is placed by hand inside the layout, above the cards. See
      // [_body].
      showBanner: false,
      // Everything that is not the deck lives in the menu: the screen is the
      // card and the three buttons under it, nothing else competing with them.
      drawer: const AppDrawer(),
      body: PopScope(
        // Back closes the conversation before it leaves the deck. Anything else
        // would drop the reader out of the app from inside a thread.
        canPop: !_threadOpen,
        onPopInvokedWithResult: (bool didPop, Object? _) {
          if (!didPop) unawaited(_closeThread());
        },
        child: Stack(
          children: <Widget>[
            deck.when(
              loading: () => const AppLoader(),
              error: (Object error, StackTrace stack) => ErrorView(
                message: context.l10n.storiesOfflineBody,
                onRetry: () => ref.invalidate(storiesDeckControllerProvider),
              ),
              data: _body,
            ),
            _ThreadSheet(
              animation: _sheet,
              onClose: () => unawaited(_closeThread()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(StoriesDeckState state) {
    return Column(
      children: <Widget>[
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
      // Pass and like consume the card. The thread and sharing leave it in
      // place: coming back from either should land on the same story.
      dismissOn: const <DeckSwipeDirection>{
        DeckSwipeDirection.left,
        DeckSwipeDirection.right,
      },
      onSwipe: _run,
      overlayBuilder: (BuildContext context, DeckSwipeProgress progress) =>
          _Badges(progress: progress),
      builder: (BuildContext context, DeckCard card, int depth) =>
          switch (card as StoryDeckItem) {
            StoryCard(:final Story story) => StoryCardView(
              story: story,
              onMore: depth == 0 ? () => unawaited(_moderate()) : null,
              onReadMore: depth == 0 ? () => unawaited(_openThread()) : null,
            ),
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
        unawaited(_pass());
      case DeckSwipeDirection.down:
        unawaited(_share());
      case DeckSwipeDirection.right:
        unawaited(_like());
      case DeckSwipeDirection.up:
        unawaited(_openThread());
      case DeckSwipeDirection.none:
        break;
    }
  }

  /// Down: the story as a 1080x1920 image for TikTok, Instagram or WhatsApp,
  /// with a link back to its thread. The growth loop of the whole app.
  ///
  /// Group stories never leave the group: sharing one outside would break the
  /// only promise a private deck makes.
  Future<void> _share() async {
    final StoryDeckItem? top = ref
        .read(storiesDeckControllerProvider)
        .value
        ?.current;
    if (top is! StoryCard) return;
    final AppLocalizations l10n = context.l10n;
    if (ref.read(feedQueryProvider).groupId != null) {
      context.showSnack(l10n.shareGroupBlocked);
      return;
    }

    final Story story = top.story;
    final String link = LinksConfig.story(story.id);
    try {
      await ref
          .read(storyShareServiceProvider)
          .share(
            storyId: story.id,
            body: story.body,
            cta: l10n.shareCta,
            link: link,
            message: l10n.shareMessage(link),
            tag: story.chapter > 1 ? l10n.storiesChapter(story.chapter) : null,
          );
    } on Object {
      if (mounted) context.showSnack(l10n.shareError);
    }
  }

  Future<void> _pass() async {
    await ref.read(storiesDeckControllerProvider.notifier).pass();
    _countCardForAds();
    _maybeShowUndoHint();
  }

  Future<void> _like() async {
    await ref.read(storiesDeckControllerProvider.notifier).like();
    _countCardForAds();
  }

  /// Shake: the last story swiped away comes back on top.
  ///
  /// Only while the deck is what the reader is looking at: not under a thread,
  /// not under another screen pushed on top.
  void _undo() {
    if (!mounted || _threadOpen) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final bool undone = ref.read(storiesDeckControllerProvider.notifier).undo();
    if (undone) unawaited(HapticFeedback.mediumImpact());
  }

  /// The first pass tells the reader a shake undoes it. Once ever: a gesture
  /// nobody can see has to be said out loud at least one time.
  void _maybeShowUndoHint() {
    final KeyValueStore store = ref.read(keyValueStoreProvider);
    if (store.getBool(_undoHintKey) || !mounted) return;
    unawaited(store.setBool(_undoHintKey, value: true));
    context.showSnack(context.l10n.storiesUndoHint);
  }

  /// Up swipe: the conversation takes over, carrying on from where the drag
  /// left the sheet.
  ///
  /// The card stays underneath and is not consumed. Closing the sheet puts the
  /// reader back on the same story, which is the only thing that makes a trip
  /// into a thread feel like a detour rather than a mistake.
  Future<void> _openThread() async {
    final Story? story = ref
        .read(storiesDeckControllerProvider.notifier)
        .markTopAsJoined();
    if (story == null) return;

    setState(() => _threadOpen = true);
    // Started before the join finishes: the sheet is already half way up from
    // the drag, and stopping it there to wait for a round trip is exactly the
    // stutter this whole arrangement exists to avoid. The panel shows its own
    // loading state.
    unawaited(_sheet.animateTo(1, curve: Curves.easeOutCubic));
    await ref.read(threadControllerProvider.notifier).open(story);

    // Entering a thread is the moment the app is worth asking for a review.
    // Cards passed by a fast thumb are not what anybody came here for.
    unawaited(ref.read(reviewServiceProvider).requestReviewAfterSuccess());
  }

  Future<void> _closeThread() async {
    if (!_threadOpen) return;
    await _sheet.animateBack(0, curve: Curves.easeInCubic);
    if (!mounted) return;
    setState(() => _threadOpen = false);
    await ref.read(threadControllerProvider.notifier).close();
  }

  /// Report or block, from the button on the top card.
  ///
  /// A menu behind a button and never a gesture: all four directions of the
  /// deck are already taken, and reporting somebody is not a thing that should
  /// ever happen by a thumb slipping.
  Future<void> _moderate() async {
    final AppLocalizations l10n = context.l10n;
    final _StoryAction? action = await showModalBottomSheet<_StoryAction>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Sharing is also the down swipe; here it can be found.
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: Text(l10n.storiesShare),
              onTap: () => Navigator.of(context).pop(_StoryAction.share),
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(l10n.storiesReport),
              onTap: () => Navigator.of(context).pop(_StoryAction.report),
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: Text(l10n.moderationBlockAuthor),
              onTap: () => Navigator.of(context).pop(_StoryAction.block),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    final StoriesDeckController deck = ref.read(
      storiesDeckControllerProvider.notifier,
    );

    switch (action) {
      case _StoryAction.share:
        await _share();
      case _StoryAction.report:
        final ReportReason? reason = await pickReportReason(context);
        if (reason == null) return;
        await deck.reportTop(reason: reason.id);
        if (!mounted) return;
        context.showSnack(
          reason == ReportReason.namesSomeone
              ? l10n.reportNamesSomeoneDone
              : l10n.storiesReportDone,
        );
      case _StoryAction.block:
        final bool ok = await showConfirmDialog(
          context,
          title: l10n.moderationBlockConfirmTitle,
          body: l10n.moderationBlockConfirmBody,
          confirmLabel: l10n.moderationBlock,
        );
        if (!ok) return;
        try {
          await deck.blockTopAuthor();
          if (mounted) context.showSnack(l10n.moderationBlocked);
        } on Object {
          if (mounted) context.showSnack(l10n.moderationError);
        }
    }
  }

  Future<void> _restart() =>
      ref.read(storiesDeckControllerProvider.notifier).restart();

  /// One consumed card is one "value action" for the interstitial pacing.
  ///
  /// The service decides whether anything actually shows: both the action count
  /// and the three minute floor have to be satisfied.
  void _countCardForAds() {
    if (!AppConfig.interstitialsEnabled) return;
    if (!ref.read(adsInitializedProvider)) return;
    unawaited(
      ref.read(adsServiceProvider).registerActionAndMaybeShowInterstitial(),
    );
  }
}

class _Exhausted extends ConsumerWidget {
  const _Exhausted({required this.onRestart});

  final Future<void> Function() onRestart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final FeedQuery query = ref.watch(feedQueryProvider);
    final FeedQueryController filters = ref.read(feedQueryProvider.notifier);

    // Out of stories in the reader's own country: the obvious next step is
    // the rest of the world, one tap away, before anything else.
    if (query.countryCode != null) {
      return EmptyState(
        icon: Icons.travel_explore,
        title: l10n.storiesCountryEmptyTitle,
        message: l10n.storiesCountryEmptyBody,
        action: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FilledButton.icon(
              onPressed: () => filters.selectCountry(null),
              icon: const Icon(Icons.public),
              label: Text(l10n.storiesWidenSearch),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => context.goNamed(AppRoutes.composeName),
              child: Text(l10n.storiesEmptyWrite),
            ),
          ],
        ),
      );
    }

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
          icon: Icons.ios_share,
          direction: DeckSwipeDirection.down,
          alignment: Alignment.topCenter,
          amount: progress.amountFor(DeckSwipeDirection.down),
        ),
      ],
    );
  }
}

/// The buttons under the deck, one per gesture.
///
/// Not decorative: a drag-only surface is unusable with a screen reader and is
/// penalised by Play's accessibility scan.
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

enum _StoryAction { share, report, block }

/// The conversation, rising out of the bottom of the deck.
///
/// It is laid out as a fraction of the screen height driven by [animation], so
/// the same value carries the movement from the finger to the controller
/// without a seam. Below a sliver of progress it is not built at all: an empty
/// deck must not pay for a panel nobody is dragging towards.
class _ThreadSheet extends StatelessWidget {
  const _ThreadSheet({required this.animation, required this.onClose});

  final Animation<double> animation;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final double t = animation.value;
        if (t <= 0.001) return const SizedBox.shrink();

        return Stack(
          children: <Widget>[
            // The deck dims as the sheet climbs, so the card underneath reads
            // as context rather than as something still being swiped.
            IgnorePointer(
              ignoring: t < 0.5,
              child: GestureDetector(
                onTap: onClose,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.45 * t),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(heightFactor: t, child: child),
            ),
          ],
        );
      },
      child: ThreadPanel(onClose: onClose),
    );
  }
}
