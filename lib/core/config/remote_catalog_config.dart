/// Where the app looks for extra questions after it ships.
///
/// ## Why a static JSON file and not Firebase
///
/// The problem is narrow: publish more questions without going through review.
/// Remote Config and Firestore both solve it, and both cost `firebase_core`
/// plus a second SDK, a `google-services.json` in the build, several MB of AAB
/// and work on every cold start. A JSON file on a CDN costs **one HTTP GET and
/// zero dependencies**, is free forever at this scale, and — because the file
/// lives in a git repository — every content release is a commit with a diff
/// and a history, which is exactly what a hand-curated catalogue wants.
///
/// GitHub Pages is the recommended host: free, CDN-backed, sends `ETag`, and
/// updating the catalogue is a `git push`. Any static host works; only
/// [url] changes.
///
/// ## Setting it up
///
/// 1. In the repo, create a `docs/` folder with `facts.json` inside.
/// 2. Settings → Pages → Source: `main` branch, `/docs` folder.
/// 3. Put the resulting URL in [url]:
///    `https://<usuario>.github.io/<repo>/facts.json`
///
/// The file uses the **same shape** as the bundled asset, so the two are
/// interchangeable and the same tooling works on both:
///
/// ```json
/// {
///   "version": 2,
///   "facts": [ { "id": "...", "category": "cuerpo", ... } ],
///   "removed": ["id-de-un-dato-que-resultó-falso"]
/// }
/// ```
///
/// See §3.6 of CLAUDE.md for the publishing procedure.
abstract final class RemoteCatalogConfig {
  /// Empty until the file is published.
  ///
  /// Like an empty ad unit or an empty contributions endpoint, an empty URL
  /// simply disables the remote layer: the app runs on the bundled catalogue
  /// exactly as it does today.
  static const String url = '';

  static bool get isConfigured => url.isNotEmpty;

  /// The fetch is background work nobody is waiting on, so it can afford to be
  /// patient — but not forever on a dying connection.
  static const Duration requestTimeout = Duration(seconds: 20);

  /// Anything bigger than this is treated as a wrong URL rather than a
  /// catalogue. At ~1 KB per question this is room for thousands.
  static const int maxPayloadBytes = 4 * 1024 * 1024;

  /// File the last good download is kept in, inside the app's support
  /// directory.
  static const String cacheFileName = 'remote_facts.json';
}
