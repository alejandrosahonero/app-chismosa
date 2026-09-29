import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Calls [onShake] when the phone is shaken on purpose.
///
/// A shake is two strong jolts within [_window]: one alone is a bump, a step or
/// the phone landing on a table. After firing it stays quiet for [_cooldown] so
/// one long shake is one event, not three.
///
/// Uses the user accelerometer (gravity already removed), so holding the phone
/// at any angle reads as zero.
class ShakeDetector {
  ShakeDetector({required this.onShake});

  /// m/s². About 1.5 g on top of gravity: a flick of the wrist, not a walk.
  static const double _threshold = 15;
  static const Duration _window = Duration(milliseconds: 600);
  static const Duration _cooldown = Duration(milliseconds: 1200);

  final void Function() onShake;

  StreamSubscription<UserAccelerometerEvent>? _subscription;
  DateTime? _firstJolt;
  DateTime _quietUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Starts listening. Safe to call twice.
  void start() {
    // No shaking a laptop: on the web the deck answers the arrow keys instead.
    // Checked first because `Platform` itself throws in a browser.
    if (kIsWeb) return;
    // Widget tests have no sensor channel, and a missing plugin fails them.
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    _subscription ??=
        userAccelerometerEventStream(
          samplingPeriod: SensorInterval.uiInterval,
        ).listen(
          _onEvent,
          // A phone without an accelerometer simply never shakes.
          onError: (Object _) => stop(),
          cancelOnError: true,
        );
  }

  /// Stops listening, so the sensor does not run while the app is hidden.
  void stop() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _firstJolt = null;
  }

  void _onEvent(UserAccelerometerEvent e) {
    final double force = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (force < _threshold) return;

    final DateTime now = DateTime.now();
    if (now.isBefore(_quietUntil)) return;

    final DateTime? first = _firstJolt;
    if (first == null || now.difference(first) > _window) {
      _firstJolt = now;
      return;
    }
    _firstJolt = null;
    _quietUntil = now.add(_cooldown);
    onShake();
  }
}
