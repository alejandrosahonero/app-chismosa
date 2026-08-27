import 'dart:math';

import 'package:flutter/material.dart';

/// A button that throws a heart into the air every time it is pressed.
///
/// Modelled on the Instagram double-tap: the reward for mashing it is that
/// mashing it looks good. That matters more than it sounds — this button is the
/// only thing on the "deck finished" screen that gives the user something back
/// immediately, and the count it feeds is only worth reading if people enjoy
/// pressing it.
///
/// Each press spawns an independent [_FloatingHeart] with its own short
/// controller, which removes itself when it lands. No press waits for the
/// previous animation, so twenty taps produce twenty overlapping hearts rather
/// than one restarting over and over.
class HeartBurstButton extends StatefulWidget {
  const HeartBurstButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;

  /// Fired on every press, including the fast repeats.
  final VoidCallback onPressed;

  @override
  State<HeartBurstButton> createState() => _HeartBurstButtonState();
}

class _HeartBurstButtonState extends State<HeartBurstButton>
    with TickerProviderStateMixin {
  final List<_Heart> _hearts = <_Heart>[];
  final Random _random = Random();

  /// Only ever increases, so two hearts alive at once can never share a key.
  int _nextId = 0;

  /// Squeezes the button itself on each press, so the tap feels connected to
  /// the heart even when the hearts drift away from the finger.
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    lowerBound: 0,
    upperBound: 0.08,
  );

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _onPressed() {
    setState(() {
      _hearts.add(
        _Heart(
          id: _nextId++,
          // Spread across the button so a burst looks like a handful thrown
          // up, not a single column.
          dx: _random.nextDouble() * 2 - 1,
          drift: _random.nextDouble() * 2 - 1,
          tilt: _random.nextDouble() * 0.6 - 0.3,
          scale: 0.75 + _random.nextDouble() * 0.55,
        ),
      );
    });

    _press.forward(from: 0).then((_) {
      if (mounted) _press.reverse();
    });

    widget.onPressed();
  }

  void _remove(int id) {
    if (!mounted) return;
    setState(() => _hearts.removeWhere((_Heart heart) => heart.id == id));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      // The hearts fly well above the button, and the button sits inside a
      // column that would otherwise cut them off.
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: <Widget>[
        AnimatedBuilder(
          animation: _press,
          builder: (BuildContext context, Widget? child) =>
              Transform.scale(scale: 1 - _press.value, child: child),
          child: FilledButton.tonalIcon(
            onPressed: _onPressed,
            icon: const Icon(Icons.favorite),
            label: Text(widget.label),
          ),
        ),
        // Above the button and untouchable: a heart mid-flight must never eat
        // the next tap.
        Positioned.fill(
          child: IgnorePointer(
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                for (final _Heart heart in _hearts)
                  _FloatingHeart(
                    key: ValueKey<int>(heart.id),
                    heart: heart,
                    onDone: () => _remove(heart.id),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The randomised parameters of one heart, fixed when it is spawned.
@immutable
class _Heart {
  const _Heart({
    required this.id,
    required this.dx,
    required this.drift,
    required this.tilt,
    required this.scale,
  });

  final int id;

  /// Horizontal start, -1 (left edge) to 1 (right edge).
  final double dx;

  /// How far it slides sideways on the way up, same scale.
  final double drift;

  final double tilt;
  final double scale;
}

class _FloatingHeart extends StatefulWidget {
  const _FloatingHeart({required this.heart, required this.onDone, super.key});

  final _Heart heart;
  final VoidCallback onDone;

  @override
  State<_FloatingHeart> createState() => _FloatingHeartState();
}

class _FloatingHeartState extends State<_FloatingHeart>
    with SingleTickerProviderStateMixin {
  static const double _rise = 150;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1100),
        )..addStatusListener((AnimationStatus status) {
          if (status == AnimationStatus.completed) widget.onDone();
        });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double t = _controller.value;

        // Fast out of the button, then coasting: a heart that rises linearly
        // reads as a loading spinner.
        final double rise = Curves.easeOutCubic.transform(t) * _rise;
        final double sway = sin(t * pi) * widget.heart.drift * 26;

        // Pops to full size in the first fifth, holds, then fades out over the
        // last third — so the burst is legible even when it is a wall of them.
        final double pop = t < 0.2
            ? Curves.easeOutBack.transform(t / 0.2)
            : 1.0;
        final double opacity = t < 0.65 ? 1.0 : 1 - (t - 0.65) / 0.35;

        return Align(
          alignment: Alignment(widget.heart.dx * 0.7, 0),
          child: Transform.translate(
            offset: Offset(sway, -rise),
            child: Transform.rotate(
              angle: widget.heart.tilt * t,
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: pop * widget.heart.scale,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: Icon(
        Icons.favorite,
        size: 30,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
