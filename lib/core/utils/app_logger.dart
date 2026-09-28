import 'dart:async';
import 'dart:developer' as developer;

import 'package:chismosa/core/config/crash_config.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Minimal logging facade.
///
/// `print` is banned by the analyzer: it survives into release builds and slows
/// down the platform channel. Everything goes through `dart:developer`, which
/// is stripped in release mode by [kDebugMode] guards.
///
/// [error] forwards to Sentry (release only, see [CrashConfig]): the SDK is
/// used here and in `bootstrap.dart`, nowhere else.
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
    if (CrashConfig.enabled && error != null) {
      unawaited(
        Sentry.captureException(
          error,
          stackTrace: stackTrace,
          hint: Hint.withMap(<String, Object>{'message': message}),
        ),
      );
    }
  }
}
