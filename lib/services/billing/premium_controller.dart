import 'dart:async';

import 'package:aja/core/utils/app_logger.dart';
import 'package:aja/services/billing/premium_service.dart';
import 'package:aja/services/billing/premium_state.dart';
import 'package:aja/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

final Provider<PremiumService> premiumServiceProvider =
    Provider<PremiumService>(
      (Ref ref) => PremiumService(ref.watch(secureStoreProvider)),
    );

/// Owns the premium entitlement for the whole app lifetime.
///
/// keepAlive (Riverpod's default for a non `autoDispose` provider) is
/// deliberate here: the purchase stream must stay subscribed from boot, because
/// a purchase can complete while the user is on any screen — or while the app
/// was closed.
final AsyncNotifierProvider<PremiumController, PremiumStatus>
premiumControllerProvider =
    AsyncNotifierProvider<PremiumController, PremiumStatus>(
      PremiumController.new,
    );

/// Synchronous read of the entitlement for call sites that cannot await
/// (ad gating, widget builds). Defaults to "not premium" while loading, which
/// is the safe direction: worst case the user briefly sees an ad they paid to
/// remove, instead of everyone getting premium for free.
final Provider<bool> isPremiumProvider = Provider<bool>((Ref ref) {
  return ref.watch(
    premiumControllerProvider.select(
      (AsyncValue<PremiumStatus> value) => value.value?.isPremium ?? false,
    ),
  );
});

class PremiumController extends AsyncNotifier<PremiumStatus> {
  late final PremiumService _service = ref.read(premiumServiceProvider);
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  @override
  Future<PremiumStatus> build() async {
    _subscription = _service.purchaseStream.listen(
      _handlePurchases,
      onError: (Object error, StackTrace stackTrace) => AppLogger.error(
        'Purchase stream error',
        name: 'billing',
        error: error,
        stackTrace: stackTrace,
      ),
    );
    ref.onDispose(() => unawaited(_subscription?.cancel()));

    // Cached entitlement first: it lets the first frame render without ads for
    // a paying user, before the store round-trip completes.
    final bool cached = await _service.readCachedEntitlement();
    final bool storeAvailable = await _service.isStoreAvailable();

    if (!storeAvailable) {
      return PremiumStatus(isPremium: cached, storeAvailable: false);
    }

    final ProductDetails? product = await _service.queryRemoveAdsProduct();

    // Ask the store to re-emit owned purchases; `_handlePurchases` verifies
    // them and updates the entitlement. Not awaited: the UI must not wait.
    unawaited(_service.restorePurchases());

    return PremiumStatus(
      isPremium: cached,
      storeAvailable: true,
      removeAdsProduct: product,
    );
  }

  /// Starts the Play purchase sheet. The result arrives through the stream.
  Future<void> buyRemoveAds() async {
    final PremiumStatus? current = state.value;
    final ProductDetails? product = current?.removeAdsProduct;
    if (current == null || product == null) return;

    state = AsyncData<PremiumStatus>(
      current.copyWith(flow: const PurchasePending()),
    );

    try {
      await _service.buyRemoveAds(product);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'buyNonConsumable failed',
        name: 'billing',
        error: error,
        stackTrace: stackTrace,
      );
      _updateFlow(const PurchaseFailed('purchase-failed'));
    }
  }

  Future<void> restorePurchases() => _service.restorePurchases();

  void _handlePurchases(List<PurchaseDetails> purchases) {
    for (final PurchaseDetails purchase in purchases) {
      unawaited(_handleSinglePurchase(purchase));
    }
  }

  Future<void> _handleSinglePurchase(PurchaseDetails purchase) async {
    switch (purchase.status) {
      case PurchaseStatus.pending:
        _updateFlow(const PurchasePending());

      case PurchaseStatus.error:
        AppLogger.error(
          'Purchase error: ${purchase.error?.message}',
          name: 'billing',
        );
        _updateFlow(const PurchaseFailed('purchase-failed'));

      case PurchaseStatus.canceled:
        _updateFlow(const PurchaseIdle());

      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        if (_service.isValidPurchase(purchase)) {
          await _service.persistEntitlement(purchase);
          _grantEntitlement();
        } else {
          AppLogger.error(
            'Rejected purchase for ${purchase.productID}',
            name: 'billing',
          );
        }
    }

    // Always acknowledge, including failed and rejected purchases: an
    // unacknowledged purchase is auto-refunded after three days.
    await _service.completePurchase(purchase);
  }

  void _grantEntitlement() {
    if (!ref.mounted) return;
    final PremiumStatus current =
        state.value ??
        const PremiumStatus(isPremium: false, storeAvailable: true);
    state = AsyncData<PremiumStatus>(
      current.copyWith(isPremium: true, flow: const PurchaseIdle()),
    );
  }

  void _updateFlow(PurchaseFlow flow) {
    if (!ref.mounted) return;
    final PremiumStatus? current = state.value;
    if (current == null) return;
    state = AsyncData<PremiumStatus>(current.copyWith(flow: flow));
  }
}
