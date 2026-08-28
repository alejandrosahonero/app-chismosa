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

  /// Where a story is written. A screen and not a bottom sheet: 600 characters
  /// with the keyboard up needs the whole height, and a sheet that covers
  /// itself is how a half-written story gets lost.
  static const String composePath = '/compose';
  static const String composeName = 'compose';

  /// The community rules. Linked from the compose screen and from Settings —
  /// the moment the rules matter is the moment somebody is about to publish.
  static const String rulesPath = '/rules';
  static const String rulesName = 'rules';

  /// Conversations this reader has joined. The only place a story can be
  /// found again: the deck deals a card once and never brings it back.
  static const String threadsPath = '/threads';
  static const String threadsName = 'threads';

  /// One conversation, reached from the history. The deck raises the same
  /// panel as a sheet instead of navigating, because there the card is still
  /// underneath.
  static const String threadPath = '/thread/:id';
  static const String threadName = 'thread';

  /// Languages the deck deals in.
  static const String languagesPath = '/languages';
  static const String languagesName = 'languages';

  /// Paywall. Reachable by deep link so a campaign can land directly on it.
  static const String paywallPath = '/premium';
  static const String paywallName = 'premium';
}
