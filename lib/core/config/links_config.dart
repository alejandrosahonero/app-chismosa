/// Public https links: shared stories and group invites.
///
/// `https` and not the `chismosa://` scheme because a custom scheme is not a
/// link anywhere that matters — WhatsApp, Instagram, TikTok and most mail apps
/// print it as plain text. An https link is tappable everywhere; with Android
/// App Links verified it opens the app directly, and without the app installed
/// it lands on a page that offers Google Play (`site/`).
///
/// The host must match three places, which is why it lives here once:
/// the intent filter in `AndroidManifest.xml`, the site deployed from `site/`
/// (with `.well-known/assetlinks.json`), and this constant.
abstract final class LinksConfig {
  static const String host = 'chismosa-app.github.io';

  static String story(String storyId) => 'https://$host/s/$storyId';

  static String invite(String code) => 'https://$host/g/$code';

  /// Store listing, for the fallback page and the share text.
  static const String playStore =
      'https://play.google.com/store/apps/details?id=com.alejandrosahonero.chismosa';
}
