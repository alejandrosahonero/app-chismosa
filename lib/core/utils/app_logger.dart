import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Minimal logging facade.
///
/// `print` is banned by the analyzer: it survives into release builds and slows
/// down the platform channel. Everything goes through `dart:developer`, which
/// is stripped in release mode by [kDebugMode] guards.
///
/// When crash reporting is added (Crashlytics / Sentry), forward [error] from
/// here instead of sprinkling the SDK across the codebase.
abstract final class AppLogger {
  static void debug(String message, {String name = 'app'}) {
    if (!kDebugMode) return;
    developer.log(message, name: name);
  }

  static void error(
    String message, {
    String name = 'app',
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: name,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
    // TODO(crash-reporting): forward to Crashlytics/Sentry before v1 release.
  }
}
