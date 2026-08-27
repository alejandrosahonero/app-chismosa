import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Outcome of the purchase flow currently running.
///
/// Modelled as a sealed union instead of a pair of booleans so the UI cannot
/// render an impossible combination (`pending && failed`).
sealed class PurchaseFlow {
  const PurchaseFlow();
}

/// No purchase in flight.
final class PurchaseIdle extends PurchaseFlow {
  const PurchaseIdle();
}

/// The Play billing sheet is open, or the purchase is awaiting approval
/// (slow payment methods, family approval).
final class PurchasePending extends PurchaseFlow {
  const PurchasePending();
}

/// The last purchase attempt failed. [message] is already user-facing.
final class PurchaseFailed extends PurchaseFlow {
  const PurchaseFailed(this.message);

  final String message;
}

/// Snapshot of the premium entitlement and the store.
///
/// The async loading/error dimension is handled by `AsyncValue`; this class
/// only carries resolved data.
@immutable
class PremiumStatus {
  const PremiumStatus({
    required this.isPremium,
    required this.storeAvailable,
    this.removeAdsProduct,
    this.flow = const PurchaseIdle(),
  });

  /// Entitlement. The single source of truth for "should we show ads".
  final bool isPremium;

  /// False when Google Play billing is missing or disabled on the device.
  /// The app must stay fully usable in that case: we simply hide the paywall.
  final bool storeAvailable;

  /// Null until the product query resolves, or when the product does not
  /// exist yet in Play Console.
  final ProductDetails? removeAdsProduct;

  final PurchaseFlow flow;

  bool get canBuy => storeAvailable && !isPremium && removeAdsProduct != null;

  PremiumStatus copyWith({
    bool? isPremium,
    bool? storeAvailable,
    ProductDetails? removeAdsProduct,
    PurchaseFlow? flow,
  }) {
    return PremiumStatus(
      isPremium: isPremium ?? this.isPremium,
      storeAvailable: storeAvailable ?? this.storeAvailable,
      removeAdsProduct: removeAdsProduct ?? this.removeAdsProduct,
      flow: flow ?? this.flow,
    );
  }
}
