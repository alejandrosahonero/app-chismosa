import 'package:aja/services/ads/ads_service.dart';
import 'package:aja/services/ads/consent_service.dart';
import 'package:aja/services/billing/premium_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final Provider<ConsentService> consentServiceProvider =
    Provider<ConsentService>((Ref ref) => ConsentService());

/// The ad service is a singleton for the whole app lifetime (no `autoDispose`):
/// it owns preloaded creatives and retry timers that must survive navigation.
final Provider<AdsService> adsServiceProvider = Provider<AdsService>((Ref ref) {
  final AdsService service = AdsService(
    consentService: ref.watch(consentServiceProvider),
    // `ref.read` inside a callback, never `ref.watch`: the service must read
    // the current entitlement at call time without rebuilding the provider.
    isPremium: () => ref.read(isPremiumProvider),
  );

  // When the user buys premium, drop every cached creative immediately.
  ref.listen<bool>(isPremiumProvider, (bool? previous, bool next) {
    if (next) service.disposeAds();
  });

  ref.onDispose(service.disposeAds);
  return service;
});

/// Flipped to true once `AdsService.initialize()` has finished (SDK ready and
/// consent gathered). Widgets watch this to know when it is safe to build an
/// `AdWidget`; without it the banner would stay invisible until an unrelated
/// rebuild happened to occur.
final NotifierProvider<AdsInitializationNotifier, bool> adsInitializedProvider =
    NotifierProvider<AdsInitializationNotifier, bool>(
      AdsInitializationNotifier.new,
    );

class AdsInitializationNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void markInitialized() => state = true;
}

/// Whether the EEA privacy message requires a "Privacy options" entry point in
/// Settings. Read-only and screen-scoped, so `autoDispose` is correct here.
final FutureProvider<bool> privacyOptionsRequiredProvider =
    FutureProvider<bool>(
      (Ref ref) => ref.watch(consentServiceProvider).isPrivacyOptionsRequired(),
      isAutoDispose: true,
    );
