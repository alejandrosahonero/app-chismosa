/// Route paths and names.
///
/// Never type a path literal at a call site: use these constants so a rename is
/// a single edit and deep links stay consistent with the Android intent filter
/// declared in `AndroidManifest.xml`.
abstract final class AppRoutes {
  /// The card deck. It is the whole app, so it sits at the root.
  static const String homePath = '/';
  static const String homeName = 'deck';

  static const String settingsPath = '/settings';
  static const String settingsName = 'settings';

  /// Saved cards. Premium only, but the route itself is not guarded: the screen
  /// sells the upgrade instead of pretending it does not exist.
  static const String favoritesPath = '/favorites';
  static const String favoritesName = 'favorites';

  /// Daily goal, points and ranks. Reached from the ring in the deck's app bar
  /// and from a row in Settings.
  static const String progressPath = '/progress';
  static const String progressName = 'progress';

  /// Paywall. Reachable by deep link so a campaign can land directly on it.
  static const String paywallPath = '/premium';
  static const String paywallName = 'premium';
}
