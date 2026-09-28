import 'package:chismosa/core/config/app_config.dart';

/// AdMob identifiers.
///
/// Two complete sets are kept side by side: the official Google test ids and
/// the production ones. [AppConfig.useProductionAds] decides which set is
/// exposed (release build = production), so a debug build can never request a
/// production ad unit.
///
/// The real App ID ([appId]) is declared in
/// `android/app/src/main/AndroidManifest.xml`. It is safe in debug builds: what
/// must never reach a debug build is a production *unit* id.
abstract final class AdConfig {
  // --- Official Google test unit ids -------------------------------------
  // https://developers.google.com/admob/android/test-ads
  static const String testAppId = 'ca-app-pub-3940256099942544~3347511713';
  static const String appId = 'ca-app-pub-4073049276319773~8299493462';
  static const String _testBanner = 'ca-app-pub-3940256099942544/9214589741';
  static const String _testInterstitial =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testRewarded = 'ca-app-pub-3940256099942544/5224354917';

  // --- Production unit ids (AdMob app "Chismosa") ------------------------
  // An empty id disables the format instead of crashing.
  static const String _prodBanner = 'ca-app-pub-4073049276319773/5544414176';
  static const String _prodInterstitial =
      'ca-app-pub-4073049276319773/4084916282';

  /// The unit whose server-side verification callback points at the
  /// `admob-ssv` Edge Function. Google's test unit has no callback configured,
  /// so in a debug build the video plays and **no credit arrives** — to test
  /// the whole loop, use the real unit with a device listed in
  /// [testDeviceIds].
  static const String _prodRewarded = 'ca-app-pub-4073049276319773/2590947775';

  /// Serves both the anchored adaptive banner and the medium rectangle used by
  /// the ad card inside the deck: a banner unit serves any banner size, so a
  /// second unit would only split the reporting.
  static String get bannerAdUnitId =>
      AppConfig.useProductionAds ? _prodBanner : _testBanner;

  static String get interstitialAdUnitId =>
      AppConfig.useProductionAds ? _prodInterstitial : _testInterstitial;

  /// Rewarded video that buys one extra story on a day the quota is spent.
  static String get rewardedAdUnitId =>
      AppConfig.useProductionAds ? _prodRewarded : _testRewarded;

  /// Whether the app targets children. Drives `tagForChildDirectedTreatment`
  /// and `maxAdContentRating`; must match the Play Console target audience
  /// declaration.
  static const bool isChildDirected = false;

  /// Device ids that should always receive test ads, even in a release build.
  /// The id is printed in logcat the first time the SDK requests an ad.
  static const List<String> testDeviceIds = <String>[];
}
