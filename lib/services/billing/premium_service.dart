import 'package:aja/core/config/billing_config.dart';
import 'package:aja/core/utils/app_logger.dart';
import 'package:aja/services/storage/secure_store.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Store plumbing for the non consumable "remove ads" product.
///
/// This class knows about Google Play Billing and about persisting the
/// entitlement; it holds no UI state. `PremiumController` turns its output into
/// something the widgets can render.
class PremiumService {
  /// [inAppPurchase] is injectable so tests can pass a fake store.
  PremiumService(this._secureStore, {InAppPurchase? inAppPurchase})
    : _iap = inAppPurchase ?? InAppPurchase.instance;

  final SecureStore _secureStore;
  final InAppPurchase _iap;

  /// Purchases can complete outside the app (slow payment methods, another
  /// device). The controller subscribes to this from `bootstrap`, not from the
  /// paywall screen.
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  Future<bool> isStoreAvailable() async {
    try {
      return await _iap.isAvailable();
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Billing availability check failed',
        name: 'billing',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Returns null when the product is not published yet or the query fails.
  /// Callers must degrade gracefully instead of blocking the UI.
  Future<ProductDetails?> queryRemoveAdsProduct() async {
    try {
      final ProductDetailsResponse response = await _iap.queryProductDetails(
        BillingConfig.allProductIds,
      );

      if (response.notFoundIDs.isNotEmpty) {
        AppLogger.debug(
          'Products not found in the store: ${response.notFoundIDs}',
          name: 'billing',
        );
      }

      for (final ProductDetails product in response.productDetails) {
        if (product.id == BillingConfig.removeAdsProductId) return product;
      }
      return null;
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'Product query failed',
        name: 'billing',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Launches the Play purchase sheet. The result arrives on [purchaseStream],
  /// never as a return value.
  Future<void> buyRemoveAds(ProductDetails product) {
    return _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  /// Re-emits every owned purchase on [purchaseStream]. Must be reachable from
  /// a visible button in Settings: its absence is a rejection reason.
  Future<void> restorePurchases() => _iap.restorePurchases();

  /// Acknowledging is mandatory. An unacknowledged purchase is refunded
  /// automatically by Google after three days.
  Future<void> completePurchase(PurchaseDetails purchase) {
    if (!purchase.pendingCompletePurchase) return Future<void>.value();
    return _iap.completePurchase(purchase);
  }

  /// Local validation for an app without a backend: we keep the purchase token
  /// and only trust it while the store keeps re-emitting the purchase on
  /// startup (`restorePurchases`). With a server, swap this for a call to the
  /// Google Play Developer API.
  bool isValidPurchase(PurchaseDetails purchase) {
    if (purchase.productID != BillingConfig.removeAdsProductId) return false;
    if (purchase.status != PurchaseStatus.purchased &&
        purchase.status != PurchaseStatus.restored) {
      return false;
    }
    return purchase.verificationData.serverVerificationData.isNotEmpty;
  }

  Future<bool> readCachedEntitlement() async {
    final String? token = await _secureStore.read(
      BillingConfig.entitlementStorageKey,
    );
    return token != null && token.isNotEmpty;
  }

  Future<void> persistEntitlement(PurchaseDetails purchase) {
    return _secureStore.write(
      BillingConfig.entitlementStorageKey,
      purchase.verificationData.serverVerificationData,
    );
  }

  Future<void> clearEntitlement() =>
      _secureStore.delete(BillingConfig.entitlementStorageKey);
}
