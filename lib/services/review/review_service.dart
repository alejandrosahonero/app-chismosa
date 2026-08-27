import 'package:aja/core/config/app_config.dart';
import 'package:aja/core/utils/app_logger.dart';
import 'package:aja/services/storage/key_value_store.dart';
import 'package:in_app_review/in_app_review.dart';

/// In-app review prompt (Google Play native dialog).
///
/// Google throttles the dialog silently: if you burn the quota at a bad moment
/// the user never sees it again for months. Hence the guards here — the prompt
/// is only allowed after a genuine success, on an install that is a few days
/// old, and at most once every few months.
///
/// Never call [requestReviewAfterSuccess] after an error, on app start, or from
/// a settings screen. [openStoreListing] exists for the explicit "rate the app"
/// button instead.
class ReviewService {
  /// [inAppReview] is injectable so tests can pass a fake.
  ReviewService(this._store, {InAppReview? inAppReview})
    : _review = inAppReview ?? InAppReview.instance;

  static const String _firstLaunchKey = 'review_first_launch_at';
  static const String _successCountKey = 'review_success_count';
  static const String _lastPromptKey = 'review_last_prompt_at';

  final KeyValueStore _store;
  final InAppReview _review;

  /// Records the install date on the very first launch. Called from bootstrap.
  Future<void> registerAppStart() async {
    if (_store.getDateTime(_firstLaunchKey) == null) {
      await _store.setDateTime(_firstLaunchKey, DateTime.now().toUtc());
    }
  }

  /// Counts a "value moment" and shows the review dialog when every guard
  /// passes. Returns true when the dialog was actually requested.
  Future<bool> requestReviewAfterSuccess() async {
    final int successes = _store.getInt(_successCountKey) + 1;
    await _store.setInt(_successCountKey, successes);

    if (!await _isEligible(successes)) return false;

    try {
      if (!await _review.isAvailable()) return false;
      await _review.requestReview();
      await _store.setDateTime(_lastPromptKey, DateTime.now().toUtc());
      return true;
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'requestReview failed',
        name: 'review',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<bool> _isEligible(int successes) async {
    if (successes < AppConfig.reviewMinSuccessfulActions) return false;

    final DateTime now = DateTime.now().toUtc();

    final DateTime? firstLaunch = _store.getDateTime(_firstLaunchKey);
    if (firstLaunch != null &&
        now.difference(firstLaunch) < AppConfig.reviewMinAppAge) {
      return false;
    }

    final DateTime? lastPrompt = _store.getDateTime(_lastPromptKey);
    if (lastPrompt != null &&
        now.difference(lastPrompt) < AppConfig.reviewMinInterval) {
      return false;
    }

    return true;
  }

  /// Opens the Play Store listing. Used by the explicit "Rate this app" row in
  /// Settings, where the native dialog is not appropriate.
  Future<void> openStoreListing() async {
    try {
      await _review.openStoreListing();
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'openStoreListing failed',
        name: 'review',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
