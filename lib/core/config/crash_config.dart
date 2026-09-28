import 'package:flutter/foundation.dart';

/// Crash reporting (Sentry).
///
/// The DSN is not a secret: it only lets an app send events to the project.
/// Paste it from Sentry → Project settings → Client Keys. Empty disables
/// reporting, and debug builds never report.
abstract final class CrashConfig {
  static const String sentryDsn =
      'https://95d04ee61100fb6b5f1f2e279f41efbd@o4512091394736128.ingest.de.sentry.io/4512165438554192';

  static bool get enabled => kReleaseMode && sentryDsn.isNotEmpty;
}
