import 'package:flutter/foundation.dart';

/// Immutable, compile-time application configuration.
///
/// Single place for the tunable constants so no feature code has to branch on
/// build mode by itself.
abstract final class AppConfig {
  /// Real ads (production ad unit ids) are only ever requested from a release
  /// build. Requesting production ads from a debug build is the fastest way to
  /// get an AdMob account banned for invalid traffic.
  static bool get useProductionAds => kReleaseMode;

  /// Shown in Settings. Keep in sync with `version:` in pubspec.yaml.
  static const String versionName = '1.0.0';

  // --- Ad pacing ----------------------------------------------------------

  /// Number of "value actions" between two interstitials. In Ajá a value action
  /// is one card swiped away, so this is "an interstitial every 9 cards".
  ///
  /// Combined with [minIntervalBetweenInterstitials]: BOTH conditions must be
  /// satisfied. The guide caps interstitials at ~1 every 3–4 minutes, and cards
  /// are consumed fast, so the time floor is what actually binds here.
  static const int interstitialEveryNActions = 9;

  /// Hard floor between two interstitials, regardless of the action counter.
  static const Duration minIntervalBetweenInterstitials = Duration(minutes: 3);

  /// Full screen ads are cached server-side for about an hour. Anything older
  /// is discarded and re-requested so we never show a stale creative.
  static const Duration fullScreenAdTtl = Duration(minutes: 55);

  /// Base delay for the exponential backoff used when an ad fails to load.
  static const Duration adRetryBaseDelay = Duration(seconds: 4);

  /// Maximum number of consecutive retries before giving up until the next
  /// explicit request.
  static const int adMaxRetries = 4;

  // --- In-app review pacing ----------------------------------------------

  /// Successful "value moments" required before the review prompt is allowed.
  static const int reviewMinSuccessfulActions = 5;

  /// Minimum lifetime of the install before asking for a review.
  static const Duration reviewMinAppAge = Duration(days: 3);

  /// Minimum distance between two review prompts. Google throttles the dialog
  /// anyway; asking less often keeps the quota for the good moments.
  static const Duration reviewMinInterval = Duration(days: 120);

  // --- Deck ---------------------------------------------------------------

  /// Fact cards between two ad cards in the deck.
  ///
  /// The ad card is the "native-like" slot from the monetization plan: it is
  /// swiped exactly like any other card, so it must be rare enough that the
  /// deck still feels like content. Never lower this below 5.
  static const int adCardEveryNCards = 6;

  /// Cards kept mounted in the stack (the draggable one plus the ones peeking
  /// behind it). Anything beyond this is built lazily on demand.
  static const int deckVisibleCards = 3;

  /// How deep in the stack an ad card starts **fetching** its creative.
  ///
  /// Requesting the creative and putting it on screen are two different things,
  /// and only the second one is an impression. Waiting for the card to reach
  /// the top before asking the network is what makes the ad arrive visibly
  /// late; fetching one card early means the creative is already in memory when
  /// the card comes up, so the swap is a repaint rather than a round trip.
  ///
  /// The `AdWidget` itself is still mounted only at depth 0 — see [AdDeckCard].
  /// Keep this small: every preloaded card is a request that may never be seen.
  static const int deckAdPreloadDepth = 1;

  /// Fraction of the card width a horizontal drag has to cover before it counts
  /// as a swipe instead of a hesitation.
  static const double deckSwipeThreshold = 0.28;

  /// Fraction of the card height an upward drag has to cover to count as
  /// "save to favourites". Lower than [deckSwipeThreshold] because the card is
  /// taller than it is wide, so the same fraction would mean a much longer
  /// gesture.
  static const double deckSwipeUpThreshold = 0.16;

  /// Fraction of the card height a downward drag has to cover to count as
  /// "share this question".
  ///
  /// Deliberately the longest of the four. Sharing opens the system sheet,
  /// which covers the app and interrupts the reading session, and it sits on
  /// the same axis as "save": an upward flick that lands the wrong way must not
  /// be able to reach it by accident.
  static const double deckSwipeDownThreshold = 0.26;

  /// Velocity (logical px/s) that commits a swipe regardless of distance, so a
  /// quick flick works without dragging the card across the screen.
  static const double deckSwipeVelocity = 700;

  // --- Daily question notification ---------------------------------------

  /// When the question of the day fires, in the device's local time.
  ///
  /// Evening on purpose: this is idle-curiosity content, and it competes with
  /// work in the morning and with nothing at all after dinner.
  static const int dailyQuestionHour = 20;
  static const int dailyQuestionMinute = 0;

  /// How many days are scheduled ahead on each app open.
  ///
  /// There is no server, so every notification has to be queued on the device
  /// with its question already chosen. Two weeks is the trade: long enough that
  /// a lapsed user keeps being reminded, short enough that the queue is
  /// refreshed with new questions often.
  static const int dailyQuestionDaysAhead = 14;
}
