/// Premium is decided by Google, through the server. These tests pin what the
/// app does with each answer, because that is the part that can lose somebody
/// what they paid for — or hand premium to somebody who did not.
library;

import 'dart:async';

import 'package:chismosa/core/config/billing_config.dart';
import 'package:chismosa/services/billing/premium_controller.dart';
import 'package:chismosa/services/billing/premium_service.dart';
import 'package:chismosa/services/billing/premium_state.dart';
import 'package:chismosa/services/billing/purchase_verifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class _Store implements PremiumService {
  final StreamController<List<PurchaseDetails>> stream =
      StreamController<List<PurchaseDetails>>.broadcast();
  String? cachedToken;
  final List<PurchaseDetails> completed = <PurchaseDetails>[];

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => stream.stream;

  @override
  Future<bool> isStoreAvailable() async => true;

  @override
  Future<ProductDetails?> queryRemoveAdsProduct() async => null;

  @override
  Future<void> buyRemoveAds(ProductDetails product) async {}

  @override
  Future<void> restorePurchases() async {}

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async =>
      completed.add(purchase);

  @override
  bool isValidPurchase(PurchaseDetails purchase) =>
      purchase.productID == BillingConfig.removeAdsProductId &&
      purchase.verificationData.serverVerificationData.isNotEmpty;

  @override
  Future<bool> readCachedEntitlement() async => cachedToken != null;

  @override
  Future<String?> readCachedToken() async => cachedToken;

  @override
  Future<void> persistEntitlement(PurchaseDetails purchase) async =>
      cachedToken = purchase.verificationData.serverVerificationData;

  @override
  Future<void> clearEntitlement() async => cachedToken = null;

  Future<void> dispose() => stream.close();
}

class _Verifier implements PurchaseVerifier {
  VerifyOutcome answer = VerifyOutcome.granted;
  final List<String> asked = <String>[];

  @override
  Future<VerifyOutcome> verify(String purchaseToken) async {
    asked.add(purchaseToken);
    return answer;
  }
}

PurchaseDetails _purchase({
  PurchaseStatus status = PurchaseStatus.purchased,
  String token = 'token-1',
}) => PurchaseDetails(
  productID: BillingConfig.removeAdsProductId,
  verificationData: PurchaseVerificationData(
    localVerificationData: '{}',
    serverVerificationData: token,
    source: 'google_play',
  ),
  transactionDate: '0',
  status: status,
);

void main() {
  late _Store store;
  late _Verifier verifier;
  late ProviderContainer container;

  Future<bool> premiumAfter(void Function() emit) async {
    await container.read(premiumControllerProvider.future);
    emit();
    // The stream handler is async: give it a few turns to land.
    for (int i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return container.read(isPremiumProvider);
  }

  setUp(() {
    store = _Store();
    verifier = _Verifier();
    container = ProviderContainer(
      overrides: [
        premiumServiceProvider.overrideWithValue(store),
        purchaseVerifierProvider.overrideWithValue(verifier),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await store.dispose();
  });

  test('a purchase Google confirms becomes premium', () async {
    final bool premium = await premiumAfter(
      () => store.stream.add(<PurchaseDetails>[_purchase()]),
    );
    expect(premium, isTrue);
    expect(verifier.asked, <String>['token-1']);
    expect(store.cachedToken, 'token-1');
  });

  test('a purchase Google rejects is not premium and is not cached', () async {
    verifier.answer = VerifyOutcome.denied;
    final bool premium = await premiumAfter(
      () => store.stream.add(<PurchaseDetails>[_purchase()]),
    );
    expect(premium, isFalse);
    expect(store.cachedToken, isNull);
    expect(
      container.read(premiumControllerProvider).value?.flow,
      isA<PurchaseFailed>(),
    );
  });

  test(
    'a server hiccup never takes away what the user just paid for',
    () async {
      verifier.answer = VerifyOutcome.unavailable;
      final bool premium = await premiumAfter(
        () => store.stream.add(<PurchaseDetails>[_purchase()]),
      );
      expect(premium, isTrue);
      // Cached, so the next start asks the server again.
      expect(store.cachedToken, 'token-1');
    },
  );

  test('every purchase is acknowledged, even a rejected one', () async {
    verifier.answer = VerifyOutcome.denied;
    await premiumAfter(() => store.stream.add(<PurchaseDetails>[_purchase()]));
    expect(store.completed, hasLength(1));
  });

  test('a refund found on the next start removes premium', () async {
    store.cachedToken = 'token-1';
    await container.read(premiumControllerProvider.future);
    expect(container.read(isPremiumProvider), isTrue);

    verifier.answer = VerifyOutcome.denied;
    await container.read(premiumControllerProvider.notifier).reverify();

    expect(container.read(isPremiumProvider), isFalse);
    expect(store.cachedToken, isNull);
  });

  test('an unreachable server on start leaves premium as it was', () async {
    store.cachedToken = 'token-1';
    await container.read(premiumControllerProvider.future);

    verifier.answer = VerifyOutcome.unavailable;
    await container.read(premiumControllerProvider.notifier).reverify();

    expect(container.read(isPremiumProvider), isTrue);
  });

  test('a purchase of some other product is ignored', () async {
    final PurchaseDetails other = PurchaseDetails(
      productID: 'something_else',
      verificationData: PurchaseVerificationData(
        localVerificationData: '{}',
        serverVerificationData: 't',
        source: 'google_play',
      ),
      transactionDate: '0',
      status: PurchaseStatus.purchased,
    );
    final bool premium = await premiumAfter(
      () => store.stream.add(<PurchaseDetails>[other]),
    );
    expect(premium, isFalse);
    expect(verifier.asked, isEmpty);
  });
}
