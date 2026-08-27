import 'dart:math' as math;

import 'package:aja/core/config/app_config.dart';
import 'package:aja/features/facts/domain/deck_item.dart';
import 'package:aja/features/facts/presentation/widgets/deck_swipe_progress.dart';
import 'package:flutter/material.dart';

/// Tinder-style card stack.
///
/// Cards sit one behind the other; only the top one reacts to touch. Each
/// direction does something different on purpose:
///
/// * **right** — flips the card over to its answer. The card springs back to
///   the centre, it is not dismissed.
/// * **left** — throws the card away and brings the next one up.
/// * **up** — saves the card to favourites. Like the flip, it springs back:
///   saving a card is not a reason to stop reading it.
/// * **down** — shares the question as an image. Springs back too, for the
///   same reason, and asks for the longest drag of the four: it opens the
///   system share sheet on top of the app.
///
/// The widget owns nothing but the gesture: it reports every direction upwards
/// and re-reads what to paint from [items]/[index]. That is what keeps the deck
/// state (position, flip) in the controller and testable.
///
/// While a finger is down it also publishes how far the drag has got into
/// [progress], so the controls outside the deck can react to the gesture
/// without rebuilding the cards on every frame.
class SwipeDeck extends StatefulWidget {
  const SwipeDeck({
    required this.items,
    required this.index,
    required this.builder,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    required this.onSwipeUp,
    required this.onSwipeDown,
    super.key,
    this.progress,
    this.overlayBuilder,
  });

  final List<DeckItem> items;

  /// Position of the top card inside [items].
  final int index;

  /// Builds one card. [depth] is 0 for the card being dragged, 1 for the one
  /// directly behind it, and so on.
  ///
  /// Depth rather than a plain "is this the top one" flag: a card can need to
  /// start work before it is reachable — an ad slot fetches its creative one
  /// place early so it is not still loading when it arrives — and that is not
  /// expressible with a boolean.
  final Widget Function(BuildContext context, DeckItem item, int depth) builder;

  /// Dismiss the top card.
  final VoidCallback onSwipeLeft;

  /// Flip the top card.
  final VoidCallback onSwipeRight;

  /// Save the top card to favourites.
  final VoidCallback onSwipeUp;

  /// Share the top card.
  final VoidCallback onSwipeDown;

  /// Live drag state, pushed out so widgets outside the deck (the round
  /// controls) can animate with the gesture.
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
  /// lands so a fast second swipe cannot skip two cards at once.
  bool _dismissing = false;

  /// Action the released drag belonged to, held for as long as the card is
  /// settling. See [_currentProgress].
  DeckSwipeDirection? _settleDirection;

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

    final Offset velocity = details.velocity.pixelsPerSecond;

    // The dominant axis decides which action the drag was: a gesture that moved
    // 200 px up and 60 px left is an upward swipe, not a dismissal.
    if (_drag.dy.abs() > _drag.dx.abs()) {
      if (_drag.dy.isNegative) {
        final bool up =
            -_drag.dy > size.height * AppConfig.deckSwipeUpThreshold ||
            -velocity.dy > AppConfig.deckSwipeVelocity;
        if (up) widget.onSwipeUp();
      } else {
        // A bare flick commits the other three directions. Not this one: the
        // share sheet takes over the screen, so a fast gesture also has to have
        // travelled as far as a deliberate save before it counts.
        final bool down =
            _drag.dy > size.height * AppConfig.deckSwipeDownThreshold ||
            (velocity.dy > AppConfig.deckSwipeVelocity &&
                _drag.dy > size.height * AppConfig.deckSwipeUpThreshold);
        if (down) widget.onSwipeDown();
      }

      // Neither saving nor sharing consumes the card, so either way it goes
      // back to the centre.
      _settleBack();
      return;
    }

    final bool committed =
        _drag.dx.abs() > size.width * AppConfig.deckSwipeThreshold ||
        velocity.dx.abs() > AppConfig.deckSwipeVelocity;

    if (!committed) {
      _settleBack();
      return;
    }

    if (_drag.dx.isNegative) {
      _dismiss(size.width);
    } else {
      // Right means "turn the card over", so it comes back to the centre and
      // the flip animation takes it from there.
      widget.onSwipeRight();
      _settleBack();
    }
  }

  void _settleBack() => _animate(Offset.zero, dismiss: false);

  void _dismiss(double width) =>
      _animate(Offset(-width * 1.6, _drag.dy), dismiss: true);

  void _animate(Offset target, {required bool dismiss}) {
    _settle = Tween<Offset>(begin: _drag, end: target).animate(
      CurvedAnimation(
        parent: _controller,
        curve: dismiss ? Curves.easeIn : Curves.easeOutBack,
      ),
    );
    _dismissing = dismiss;
    _settleDirection = _progressFor(_drag, _size).direction;

    _controller
      ..value = 0
      ..forward().whenComplete(() {
        if (!mounted) return;
        _settle = null;
        _settleDirection = null;

        if (dismiss) {
          // `_drag` stays at the off screen target on purpose; didUpdateWidget
          // resets it once the next card is on top. The feedback does not: the
          // card is gone, so the button has nothing left to announce.
          widget.progress?.value = DeckSwipeProgress.idle;
          widget.onSwipeLeft();
          return;
        }

        setState(() => _drag = Offset.zero);
        _publish();
      });
  }

  /// Turns the raw finger offset into the action the gesture is aiming at.
  ///
  /// Only the dominant axis counts, which is the same rule [_onPanEnd] uses to
  /// decide what to fire. Sharing it here is what guarantees the badge and the
  /// button that swell mid-drag belong to the action that will actually run.
  DeckSwipeProgress _progressFor(Offset drag, Size size) {
    if (size.isEmpty || drag == Offset.zero) return DeckSwipeProgress.idle;

    if (drag.dy.abs() > drag.dx.abs()) {
      if (drag.dy.isNegative) {
        return DeckSwipeProgress(
          direction: DeckSwipeDirection.up,
          amount: (-drag.dy / (size.height * AppConfig.deckSwipeUpThreshold))
              .clamp(0.0, 1.0),
        );
      }
      return DeckSwipeProgress(
        direction: DeckSwipeDirection.down,
        amount: (drag.dy / (size.height * AppConfig.deckSwipeDownThreshold))
            .clamp(0.0, 1.0),
      );
    }

    return DeckSwipeProgress(
      direction: drag.dx.isNegative
          ? DeckSwipeDirection.left
          : DeckSwipeDirection.right,
      amount: (drag.dx.abs() / (size.width * AppConfig.deckSwipeThreshold))
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
          final DeckItem item = widget.items[i];
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

  Widget _buildTopCard(BuildContext context, DeckItem item, Size size) {
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

  Widget _buildBackCard(BuildContext context, DeckItem item, int depth) {
    // Cards behind peek out from under the top one. They never animate on
    // their own, hence the const-friendly static transform.
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
