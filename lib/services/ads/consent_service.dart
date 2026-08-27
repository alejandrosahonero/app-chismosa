import 'dart:async';

import 'package:aja/core/config/ad_config.dart';
import 'package:aja/core/utils/app_logger.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Google UMP (User Messaging Platform) wrapper.
///
/// GDPR/EEA consent is mandatory before requesting the first ad. The message
/// itself is configured in the AdMob console — this class only asks the SDK to
/// gather it and reports whether ads may be requested.
///
/// Nothing here ever throws: if consent fails, [canRequestAds] stays false and
/// the app simply runs without ads.
class ConsentService {
  bool _canRequestAds = false;

  /// True once the SDK reports that the necessary consent has been gathered.
  bool get canRequestAds => _canRequestAds;

  /// Requests an update of the consent information and shows the form if the
  /// user's region requires it. Safe to call on every cold start: the SDK
  /// caches the decision and only shows the form when needed.
  Future<void> gatherConsent() async {
    final ConsentRequestParameters params = ConsentRequestParameters(
      tagForUnderAgeOfConsent: AdConfig.isChildDirected,
    );

    final Completer<void> completer = Completer<void>();

    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        await ConsentForm.loadAndShowConsentFormIfRequired((
          FormError? error,
        ) async {
          if (error != null) {
            AppLogger.error(
              'Consent form error ${error.errorCode}: ${error.message}',
              name: 'ads',
            );
          }
          await _refreshCanRequestAds();
          if (!completer.isCompleted) completer.complete();
        });
      },
      (FormError error) async {
        AppLogger.error(
          'Consent info update failed ${error.errorCode}: ${error.message}',
          name: 'ads',
        );
        // The SDK may still allow ads with the cached consent status.
        await _refreshCanRequestAds();
        if (!completer.isCompleted) completer.complete();
      },
    );

    return completer.future;
  }

  Future<void> _refreshCanRequestAds() async {
    try {
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
    } on Object catch (error) {
      AppLogger.error('canRequestAds failed', name: 'ads', error: error);
      _canRequestAds = false;
    }
  }

  /// Whether a "Privacy options" entry must be shown in Settings. Required by
  /// the EEA privacy message; hide the row when it returns false.
  Future<bool> isPrivacyOptionsRequired() async {
    try {
      final PrivacyOptionsRequirementStatus status = await ConsentInformation
          .instance
          .getPrivacyOptionsRequirementStatus();
      return status == PrivacyOptionsRequirementStatus.required;
    } on Object catch (error) {
      AppLogger.error(
        'Privacy options status failed',
        name: 'ads',
        error: error,
      );
      return false;
    }
  }

  /// Reopens the privacy form from Settings so the user can change consent.
  Future<void> showPrivacyOptionsForm() async {
    final Completer<void> completer = Completer<void>();
    await ConsentForm.showPrivacyOptionsForm((FormError? error) async {
      if (error != null) {
        AppLogger.error(
          'Privacy options form error ${error.errorCode}: ${error.message}',
          name: 'ads',
        );
      }
      await _refreshCanRequestAds();
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }
}
