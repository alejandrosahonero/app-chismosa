/// Supabase connection settings.
///
/// ## Why Supabase and not Firebase
///
/// Chismosa needs a server: a worldwide feed, live threads, accounts and
/// moderation cannot live on the device. The question was only which free tier
/// can hold it.
///
/// Firebase loses on one detail: **deploying Cloud Functions requires the Blaze
/// plan**, which requires a credit card. Without functions there is no
/// automatic moderation, no trustworthy publishing limit and no way to send a
/// push. Supabase's free plan includes Edge Functions, and — more importantly —
/// Postgres with row level security, which turns "one story a day", "hide after
/// three reports" and "never show me someone I blocked" into rules the server
/// enforces instead of promises the client makes.
///
/// The binding limit of the free plan is **200 concurrent Realtime
/// connections**, which is why only an open thread subscribes to anything; the
/// deck is plain queries.
///
/// ## Setting it up
///
/// 1. Create a project at supabase.com (free, no card).
/// 2. Authentication → Providers → enable **Anonymous sign-ins**.
/// 3. Authentication → Providers → Email: turn **Confirm email off**
///    (the recovery code upgrades the anonymous account to an
///    unreachable e-mail address; see `AnonymousIdentityService`).
/// 4. SQL editor → run `supabase/migrations/*.sql` in order.
/// 5. Settings → API → copy the *Project URL* and the *publishable* key here.
///
/// The publishable key is meant to ship inside the app: it grants nothing on
/// its own, because every table is behind row level security.
abstract final class BackendConfig {
  /// Empty until the project exists.
  ///
  /// Like an empty ad unit id, an empty URL **disables** the backend instead of
  /// crashing: the app builds, the tests run and the deck shows its offline
  /// state. That is what lets the whole feature land before the project does.
  static const String url = 'https://sbeyvzhtvmzcalflqajv.supabase.co';

  /// The `publishable` key (labelled `anon public` in older dashboards).
  ///
  /// Never the `service_role` key: that one bypasses row level security and
  /// would hand every device full read and write access to the database.
  static const String publishableKey =
      'sb_publishable_MWswrHc_IZo3A1dU6Vkjkw_3U4lwJj9';

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;

  /// A page of the deck. Small enough to feel instant on a slow connection,
  /// big enough that the user rarely reaches the end of one mid-session.
  /// Cloudflare Turnstile site key (public by design, like the publishable
  /// key). Empty = no CAPTCHA is requested. Must be set **before** turning on
  /// "Enable CAPTCHA protection" in Supabase, or no new account can be created.
  static const String turnstileSiteKey = '';

  /// The host the Turnstile widget is registered for; Android loads the widget
  /// under this origin.
  static const String turnstileHost = 'https://chismosa-app.github.io';

  static const int feedPageSize = 30;

  /// How long the deck waits for a page before showing the offline screen.
  static const Duration requestTimeout = Duration(seconds: 15);

  /// Newest ids from the device's seen list that travel with a feed request.
  ///
  /// The full list lives on the device (same as the inherited deck did): one
  /// row per user and story would grow as users x catalogue and eat the 500 MB
  /// of the free plan by itself. Sending the tail is an optimisation — the
  /// client filters the page again — so this only has to be big enough that a
  /// page is rarely wasted.
  static const int seenIdsSentWithFeed = 300;

  /// A page of messages inside a thread.
  static const int threadPageSize = 50;
}
