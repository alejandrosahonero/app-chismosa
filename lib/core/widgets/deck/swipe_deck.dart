import 'dart:math' as math;

import 'package:chismosa/core/config/app_config.dart';
import 'package:chismosa/core/widgets/deck/deck_card.dart';
import 'package:chismosa/core/widgets/deck/deck_swipe_progress.dart';
import 'package:chismosa/core/widgets/deck/deck_thresholds.dart';
import 'package:flutter/material.dart';

/// Tinder-style card stack.
///
/// Cards sit one behind the other; only the top one reacts to touch. The widget
/// owns **nothing but the gesture**: it reports the direction upwards and
/// re-reads what to paint from [items]/[index]. That is what keeps the deck's
/// own state — position, flip, read pile — in a controller, and testable
/// without pumping a single animation.
///
/// What each direction *means* is not decided here. [dismissOn] says which
/// directions throw the card off screen and which spring back to the centre,
/// so the same widget serves a deck where left is "discard" and one where
/// three directions consume the card and the fourth opens a thread.
///
/// While a finger is down it publishes how far the drag has got into
/// [progress], so controls outside the deck can animate with the gesture
/// without rebuilding the cards on every frame.
class SwipeDeck extends StatefulWidget {
  const SwipeDeck({
    required this.items,
    required this.index,
    required this.builder,
    required this.onSwipe,
    required this.thresholds,
    super.key,
    this.dismissOn = const <DeckSwipeDirection>{DeckSwipeDirection.left},
    this.progress,
    this.overlayBuilder,
  });

  final List<DeckCard> items;

  /// Position of the top card inside [items].
  final int index;

  /// Builds one card. [depth] is 0 for the card being dragged, 1 for the one
  /// directly behind it, and so on.
  ///
  /// Depth rather than a plain "is this the top one" flag: a card can need to
  /// start work before it is reachable — an ad slot fetches its creative one
  /// place early so it is not still loading when it arrives — and that is not
  /// expressible with a boolean.
  final Widget Function(BuildContext context, DeckCard item, int depth) builder;

  /// Fired once a gesture is committed.
  ///
  /// For a direction in [dismissOn] this arrives **after** the card has flown
  /// off screen, so the parent advances exactly when the card is gone. For the
  /// others it arrives on release, while the card is springing back.
  final void Function(DeckSwipeDirection direction) onSwipe;

  /// Directions that consume the card. Everything else springs back.
  final Set<DeckSwipeDirection> dismissOn;

  final DeckThresholds thresholds;

  /// Live drag state, pushed out so widgets outside the deck can animate with
  /// the gesture.
  ///
  /// A notifier and not a callback: this changes every frame of a drag, and
  /// only the handful of widgets that listen should rebuild — not the whole
  /// screen.
  final ValueNotifier<DeckSwipeProgress>? progress;

  /// Overlay painted on top of the card and dragged along with it, so the
  /// action the current gesture would fire is readable at the card's edge.
  final Widget Function(BuildContext context, DeckSwipeProgress progress)?
  overlayBuilder;

  @override
  State<SwipeDeck> createState() => _SwipeDeckState();
}

class _SwipeDeckState extends State<SwipeDeck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  Animation<Offset>? _settle;

  /// Live finger offset of the top card, in logical pixels.
  Offset _drag = Offset.zero;

  /// Size of the card area, cached from the layout so the gesture callbacks can
  /// turn pixels into progress without a context lookup.
  Size _size = Size.zero;

  /// True while the card is flying off screen; the gesture is ignored until it
  /// lands so a fast second swipe cannot consume two cards at once.
  bool _dismissing = false;

  /// Action the released drag belonged to, held for as long as the card is
  /// settling. See [_currentProgress].
  DeckSwipeDirection? _settleDirection;

  /// Direction whose [SwipeDeck.onSwipe] fires when the fly-off lands.
  DeckSwipeDirection? _pendingDismiss;

  @override
  void initState() {
    super.initState();
    // Built here and not in a `late final` initializer: a lazy field is only
    // created the first time it is read, so a deck that was never dragged would
    // create its ticker from inside `dispose()`, with the element already
    // deactivated. That throws.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(_onSettleTick);
  }

  @override
  void didUpdateWidget(SwipeDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The dismissed card is parked off screen until the parent actually
    // advances. Snapping it back to the centre the moment the animation ends
    // would flash the old card for one frame, because the controller updates
    // the index on the next build and not synchronously.
    if (widget.index != oldWidget.index ||
        widget.items.length != oldWidget.items.length) {
      _drag = Offset.zero;
      _dismissing = false;
      _publishAfterFrame(DeckSwipeProgress.idle);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSettleTick() {
    final Animation<Offset>? settle = _settle;
    if (settle == null) return;
    setState(() => _drag = settle.value);
    _publish();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_dismissing || _controller.isAnimating) return;
    _settleDirection = null;
    setState(() => _drag += details.delta);
    _publish();
  }

  void _onPanEnd(DragEndDetails details, Size size) {
    if (_dismissing || _controller.isAnimating) return;

    final DeckSwipeDirection? committed = _committedDirection(
      details.velocity.pixelsPerSecond,
      size,
    );

    if (committed == null) {
      _settleBack();
      return;
    }

    if (widget.dismissOn.contains(committed)) {
      _dismiss(committed, size);
      return;
    }

    // Springs back to the centre: the card was not consumed, whatever the
    // gesture opened is on top of it now.
    widget.onSwipe(committed);
    _settleBack();
  }

  /// The action this release belongs to, or null if it was a hesitation.
  ///
  /// The dominant axis decides which direction it was — a gesture that moved
  /// 200 px up and 60 px left is an upward swipe, not a dismissal — and the
  /// same rule drives the live feedback, which is what guarantees the badge
  /// that lit up mid-drag is the action that actually runs.
  DeckSwipeDirection? _committedDirection(Offset velocity, Size size) {
    final DeckSwipeDirection direction = _progressFor(_drag, size).direction;
    if (direction == DeckSwipeDirection.none || size.isEmpty) return null;

    final bool vertical =
        direction == DeckSwipeDirection.up ||
        direction == DeckSwipeDirection.down;

    final double travelled = vertical ? _drag.dy.abs() : _drag.dx.abs();
    final double extent = vertical ? size.height : size.width;
    final double needed = extent * widget.thresholds.forDirection(direction);
    if (travelled >= needed) return direction;

    final double speed = vertical ? velocity.dy.abs() : velocity.dx.abs();
    if (speed < widget.thresholds.velocity) return null;

    // A flick commits most directions outright. For the ones that take the
    // screen over, it still has to have gone somewhere: half the distance, so
    // an off-axis flick cannot reach them by accident.
    if (widget.thresholds.requireTravel.contains(direction)) {
      return travelled >= needed * 0.5 ? direction : null;
    }
    return direction;
  }

  void _settleBack() => _animate(Offset.zero, dismiss: null);

  void _dismiss(DeckSwipeDirection direction, Size size) =>
      _animate(switch (direction) {
        DeckSwipeDirection.left => Offset(-size.width * 1.6, _drag.dy),
        DeckSwipeDirection.right => Offset(size.width * 1.6, _drag.dy),
        DeckSwipeDirection.up => Offset(_drag.dx, -size.height * 1.4),
        DeckSwipeDirection.down => Offset(_drag.dx, size.height * 1.4),
        DeckSwipeDirection.none => Offset.zero,
      }, dismiss: direction);

  void _animate(Offset target, {required DeckSwipeDirection? dismiss}) {
    _settle = Tween<Offset>(begin: _drag, end: target).animate(
      CurvedAnimation(
        parent: _controller,
        curve: dismiss != null ? Curves.easeIn : Curves.easeOutBack,
      ),
    );
    _dismissing = dismiss != null;
    _pendingDismiss = dismiss;
    _settleDirection = _progressFor(_drag, _size).direction;

    _controller
      ..value = 0
      ..forward().whenComplete(() {
        if (!mounted) return;
        _settle = null;
        _settleDirection = null;

        final DeckSwipeDirection? dismissed = _pendingDismiss;
        if (dismissed != null) {
          // `_drag` stays at the off screen target on purpose; didUpdateWidget
          // resets it once the next card is on top. The feedback does not: the
          // card is gone, so the button has nothing left to announce.
          _pendingDismiss = null;
          widget.progress?.value = DeckSwipeProgress.idle;
          widget.onSwipe(dismissed);
          return;
        }

        setState(() => _drag = Offset.zero);
        _publish();
      });
  }

  /// Turns the raw finger offset into the action the gesture is aiming at.
  DeckSwipeProgress _progressFor(Offset drag, Size size) {
    if (size.isEmpty || drag == Offset.zero) return DeckSwipeProgress.idle;

    final bool vertical = drag.dy.abs() > drag.dx.abs();
    final DeckSwipeDirection direction = vertical
        ? (drag.dy.isNegative ? DeckSwipeDirection.up : DeckSwipeDirection.down)
        : (drag.dx.isNegative
              ? DeckSwipeDirection.left
              : DeckSwipeDirection.right);

    final double travelled = vertical ? drag.dy.abs() : drag.dx.abs();
    final double extent = vertical ? size.height : size.width;

    return DeckSwipeProgress(
      direction: direction,
      amount: (travelled / (extent * widget.thresholds.forDirection(direction)))
          .clamp(0.0, 1.0),
    );
  }

  /// Progress as the rest of the UI should see it.
  ///
  /// `Curves.easeOutBack` overshoots the centre on the way back, which flips
  /// the sign of the drag for a few frames. Reported raw, that would blink the
  /// badge and the button of the *opposite* action at the end of every gesture,
  /// so while a card is settling only the direction it was released towards is
  /// allowed to show anything.
  DeckSwipeProgress _currentProgress() {
    final DeckSwipeProgress live = _progressFor(_drag, _size);
    final DeckSwipeDirection? settling = _settleDirection;
    if (settling == null || live.direction == settling) return live;
    return DeckSwipeProgress.idle;
  }

  void _publish() => widget.progress?.value = _currentProgress();

  /// Same as [_publish], but from a build-phase callback.
  ///
  /// Listeners of the notifier rebuild when it changes, and [didUpdateWidget]
  /// runs while the tree is already building — writing to it there would throw.
  void _publishAfterFrame(DeckSwipeProgress value) {
    final ValueNotifier<DeckSwipeProgress>? progress = widget.progress;
    if (progress == null || progress.value == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) progress.value = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        _size = size;

        // Painted back to front: the last child of a Stack is on top, and the
        // top card must be the one that receives the gesture.
        final List<Widget> cards = <Widget>[];
        final int last = math.min(
          widget.index + AppConfig.deckVisibleCards,
          widget.items.length,
        );

        for (int i = last - 1; i >= widget.index; i--) {
          final DeckCard item = widget.items[i];
          final int depth = i - widget.index;
          cards.add(
            depth == 0
                ? _buildTopCard(context, item, size)
                : _buildBackCard(context, item, depth),
          );
        }

        return Stack(fit: StackFit.expand, children: cards);
      },
    );
  }

  Widget _buildTopCard(BuildContext context, DeckCard item, Size size) {
    final DeckSwipeProgress progress = _currentProgress();

    return GestureDetector(
      key: ValueKey<String>(item.key),
      behavior: HitTestBehavior.opaque,
      onPanUpdate: _onPanUpdate,
      onPanEnd: (DragEndDetails details) => _onPanEnd(details, size),
      child: Transform.translate(
        offset: _drag,
        child: Transform.rotate(
          // Pivot below the card so it tilts like a real card being pulled off
          // a stack instead of spinning around its middle.
          origin: const Offset(0, 320),
          angle: progress.signedHorizontal * 0.12,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              widget.builder(context, item, 0),
              if (widget.overlayBuilder != null)
                IgnorePointer(child: widget.overlayBuilder!(context, progress)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackCard(BuildContext context, DeckCard item, int depth) {
    // Cards behind peek out from under the top one. They never animate on
    // their own, hence the static transform.
    return Transform.translate(
      key: ValueKey<String>(item.key),
      offset: Offset(0, depth * 12.0),
      child: Transform.scale(
        scale: 1 - depth * 0.04,
        child: IgnorePointer(child: widget.builder(context, item, depth)),
      ),
    );
  }
}
