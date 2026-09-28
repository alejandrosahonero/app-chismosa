import 'package:flutter/foundation.dart';

/// Crash reporting (Sentry).
///
/// The DSN is not a secret: it only lets an app send events to the project.
/// Paste it from Sentry → Project settings → Client Keys. Empty disables
/// reporting, and debug builds never report.
abstract final class CrashConfig {
  static const String sentryDsn = '';

  static bool get enabled => kReleaseMode && sentryDsn.isNotEmpty;
}
