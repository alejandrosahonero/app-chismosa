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
    if (CrashConfig.enabled && error != null && !isOfflineError(error)) {
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

/// Whether [error] only says the phone could not reach the server: no
/// connection, DNS down, a captive portal, a dropped socket, a timeout.
///
/// Those are the user's network, not a bug, and every call site already
/// handles them (retry buttons, cached decks). Sending them to Sentry buried
/// real crashes under "Failed host lookup" from every phone that opened the
/// app in a lift. Matched on the text rather than the type so it also covers
/// the wrappers (`ClientException`, `AuthRetryableFetchException`) and works
/// on the web build, where `dart:io` types do not exist.
bool isOfflineError(Object error) {
  if (error is TimeoutException) return true;
  final String text = error.toString();
  const List<String> signs = <String>[
    'SocketException',
    'Failed host lookup',
    'No address associated with hostname',
    'Network is unreachable',
    'Connection refused',
    'Connection reset',
    'Connection closed',
    'Connection timed out',
    'HandshakeException',
    'XMLHttpRequest error',
    'Failed to fetch',
  ];
  return signs.any(text.contains);
}
