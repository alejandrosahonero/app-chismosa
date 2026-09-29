import 'dart:async';

import 'package:chismosa/core/utils/app_logger.dart';
import 'package:chismosa/services/backend/backend_providers.dart';
import 'package:chismosa/services/billing/premium_service.dart';
import 'package:chismosa/services/billing/premium_state.dart';
import 'package:chismosa/services/billing/purchase_verifier.dart';
import 'package:chismosa/services/storage/storage_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final Provider<PremiumService> premiumServiceProvider =
    Provider<PremiumService>(
      (Ref ref) => PremiumService(ref.watch(secureStoreProvider)),
    );

final Provider<PurchaseVerifier> purchaseVerifierProvider =
    Provider<PurchaseVerifier>(
      (Ref ref) =>
          SupabasePurchaseVerifier(() => ref.read(supabaseClientProvider)),
    );

/// Owns the premium entitlement for the whole app lifetime.
///
/// **Google decides, through the server.** Every purchase and every restore
/// is checked by `verify-purchase` against the Play Developer API, and the
/// server is the only thing that can set `profiles.is_premium` — which is what
/// lifts the posting limit. The rules for each answer:
///
/// | Server says | What happens |
/// |---|---|
/// | granted | Premium, cached on the device. |
/// | denied | No premium, cache wiped. A refund lands here. |
/// | unavailable | Nothing changes. A fresh purchase counts provisionally — the user paid, and a server hiccup must not take that away — and is checked again on the next start. |
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
  PurchaseVerifier get _verifier => ref.read(purchaseVerifierProvider);
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  @override
  Future<PremiumStatus> build() async {
    if (kIsWeb) return _buildForWeb();

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

  /// The web has no Play store: premium is bought on Android and read here
  /// from the account (`profiles.is_premium`, written by `verify-purchase`),
  /// so restoring a premium account with its recovery code carries it over.
  Future<PremiumStatus> _buildForWeb() async {
    // Rebuilt when the account changes (sign-in, restore from a code).
    ref.watch(sessionEpochProvider);
    final SupabaseClient? client = ref.watch(supabaseClientProvider);
    final String? userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) {
      return const PremiumStatus(isPremium: false, storeAvailable: false);
    }
    try {
      final Map<String, dynamic>? row = await client
          .from('profiles')
          .select('is_premium')
          .eq('id', userId)
          .maybeSingle();
      return PremiumStatus(
        isPremium: row?['is_premium'] == true,
        storeAvailable: false,
      );
    } on Object catch (error) {
      AppLogger.debug('Premium lookup failed: $error', name: 'billing');
      return const PremiumStatus(isPremium: false, storeAvailable: false);
    }
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

  Future<void> restorePurchases() async {
    if (kIsWeb) return;
    await _service.restorePurchases();
  }

  /// Checks the cached purchase with the server again.
  ///
  /// Called once the backend is up on every start. Play re-emits owned
  /// purchases through `restorePurchases`, but a refunded one simply stops
  /// appearing — so without this, a refund would leave premium on forever.
  Future<void> reverify() async {
    if (kIsWeb) return;
    final String? token = await _service.readCachedToken();
    if (token == null || token.isEmpty) return;
    switch (await _verifier.verify(token)) {
      case VerifyOutcome.granted:
        _setPremium(isPremium: true);
      case VerifyOutcome.denied:
        await _service.clearEntitlement();
        _setPremium(isPremium: false);
      case VerifyOutcome.unavailable:
        break;
    }
  }

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
        if (!_service.isValidPurchase(purchase)) {
          AppLogger.error(
            'Rejected purchase for ${purchase.productID}',
            name: 'billing',
          );
          break;
        }
        final String token = purchase.verificationData.serverVerificationData;
        switch (await _verifier.verify(token)) {
          case VerifyOutcome.granted:
          case VerifyOutcome.unavailable:
            // Unavailable counts too, provisionally: see the class comment.
            // The token is cached, so the next start asks again.
            await _service.persistEntitlement(purchase);
            _setPremium(isPremium: true);
          case VerifyOutcome.denied:
            await _service.clearEntitlement();
            _setPremium(isPremium: false);
            if (purchase.status == PurchaseStatus.purchased) {
              _updateFlow(const PurchaseFailed('purchase-failed'));
            }
        }
    }

    // Always acknowledge, including failed and rejected purchases: an
    // unacknowledged purchase is auto-refunded after three days.
    await _service.completePurchase(purchase);
  }

  void _setPremium({required bool isPremium}) {
    if (!ref.mounted) return;
    final PremiumStatus current =
        state.value ??
        const PremiumStatus(isPremium: false, storeAvailable: true);
    state = AsyncData<PremiumStatus>(
      current.copyWith(
        isPremium: isPremium,
        flow: isPremium ? const PurchaseIdle() : current.flow,
      ),
    );
  }

  void _updateFlow(PurchaseFlow flow) {
    if (!ref.mounted) return;
    final PremiumStatus? current = state.value;
    if (current == null) return;
    state = AsyncData<PremiumStatus>(current.copyWith(flow: flow));
  }
}
