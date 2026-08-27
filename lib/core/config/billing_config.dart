/// Google Play Billing product configuration.
///
/// The product must exist and be **active** in Play Console (managed product,
/// non consumable) before it can be queried, and a build has to be uploaded to
/// a testing track first.
abstract final class BillingConfig {
  /// Non consumable "remove ads" entitlement. Renaming this after release
  /// orphans every existing purchase, so treat it as immutable.
  static const String removeAdsProductId = 'premium_remove_ads';

  static const Set<String> allProductIds = <String>{removeAdsProductId};

  /// Secure storage key holding the cached entitlement. Cached only to render
  /// the first frame without ads; it is always re-verified against the store.
  static const String entitlementStorageKey = 'entitlement_remove_ads';
}
