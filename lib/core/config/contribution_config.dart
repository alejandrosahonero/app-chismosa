/// Where user contributions and "ask for more" taps are sent.
///
/// ## Why a Google Apps Script web app
///
/// This app has no backend and is not going to grow one for a suggestion box.
/// The options were Firebase (Firestore), a third party form service, or a
/// Google Apps Script web app writing into a spreadsheet. The script wins here:
///
/// * **No SDK.** Firestore means `firebase_core` + `cloud_firestore`, a
///   `google-services.json` in the build, several MB of AAB and work on every
///   cold start — a heavy price for one form and one counter. This needs a
///   single POST.
/// * **Free, and already in the developer's account.** No new billing
///   relationship, no third party holding user text.
/// * **The inbox is a spreadsheet.** Sorting, filtering and marking a
///   suggestion as "already published" is what a spreadsheet is for, and the
///   catalogue is hand curated anyway.
///
/// If Firestore ever lands for the catalogue itself (Remote Config is on the
/// roadmap), move this: it is one file and one service.
///
/// ## Setting it up
///
/// 1. Create a Google Sheet with two tabs: `aportaciones` and `mas`.
/// 2. Extensions → Apps Script, and paste:
///
/// ```js
/// function doPost(e) {
///   var body = JSON.parse(e.postData.contents);
///   var book = SpreadsheetApp.getActiveSpreadsheet();
///   if (body.type === 'more_request') {
///     book.getSheetByName('mas')
///         .appendRow([new Date(), body.count, body.appVersion, body.language]);
///   } else {
///     book.getSheetByName('aportaciones')
///         .appendRow([new Date(), body.question, body.answer, body.source,
///                     body.language, body.appVersion]);
///   }
///   return ContentService.createTextOutput('ok');
/// }
/// ```
///
/// 3. Deploy → New deployment → Web app, "Execute as: me", "Who has access:
///    anyone". Copy the `/exec` URL into [endpoint].
///
/// ## Before shipping this
///
/// The endpoint is public and unauthenticated, which is fine for a suggestion
/// box and wrong for anything else. Treat every row as untrusted text: never
/// paste a contribution into the catalogue without reading it. Contributions
/// are also **user generated content leaving the device**, so the Play Data
/// Safety form has to declare it and the privacy policy has to mention it. The
/// payload carries no identifier of any kind on purpose — no ad id, no install
/// id, no device model — so the declaration stays at "user content, optional,
/// not linked to identity".
abstract final class ContributionConfig {
  /// The `/exec` URL of the deployed Apps Script.
  ///
  /// Empty until it exists. Like an empty ad unit in [AdConfig], an empty
  /// endpoint disables the network side instead of crashing: contributions
  /// still get written to the on-device outbox and the tap counter still adds
  /// up, so nothing the user does is lost, and the first build with a real URL
  /// flushes the backlog.
  static const String endpoint = '';

  static bool get isConfigured => endpoint.isNotEmpty;

  /// Minimum gap between two accepted contributions.
  ///
  /// A suggestion box with an open endpoint invites a bored user with a stuck
  /// finger. Long enough to stop that, short enough that somebody with two real
  /// ideas is not told to come back tomorrow.
  static const Duration minIntervalBetweenContributions = Duration(seconds: 30);

  /// Length limits, enforced before anything is stored or sent.
  static const int minQuestionLength = 10;
  static const int maxQuestionLength = 200;
  static const int minAnswerLength = 2;
  static const int maxAnswerLength = 400;
  static const int maxSourceLength = 200;

  /// Contributions kept on device while the endpoint is unreachable. Past this
  /// the oldest is dropped: an outbox that grows without limit is a bug report
  /// about storage waiting to happen.
  static const int maxOutboxSize = 50;

  /// How long to wait after the last "ask for more" tap before sending the
  /// batch. The button is meant to be mashed, so the taps are counted locally
  /// and travel as one number.
  static const Duration moreRequestFlushDelay = Duration(seconds: 3);

  /// Timeout for a single POST. Generous: this is background work nobody is
  /// waiting on, and a retry costs more than a slow success.
  static const Duration requestTimeout = Duration(seconds: 15);
}
