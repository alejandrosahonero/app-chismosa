import 'package:chismosa/core/config/billing_config.dart';
import 'package:chismosa/core/utils/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What Google Play said about a purchase token, through the server.
enum VerifyOutcome {
  /// A real, paid purchase of this app. The server has already set
  /// `profiles.is_premium`.
  granted,

  /// Not a purchase of this app, or refunded / cancelled. Premium goes.
  denied,

  /// Could not ask: no connection, no session yet, Play or the function down.
  /// Nothing is decided; the app keeps what it had and asks again later.
  unavailable,
}

/// Checks a purchase token with Google Play through the `verify-purchase`
/// Edge Function.
///
/// An interface so the premium controller can be tested without a server:
/// the rules about *what to do* with each answer are the part that has to be
/// right, and they live in the controller.
abstract interface class PurchaseVerifier {
  Future<VerifyOutcome> verify(String purchaseToken);
}

class SupabasePurchaseVerifier implements PurchaseVerifier {
  const SupabasePurchaseVerifier(this._client);

  /// Read at call time: the client only exists after the first frame, and a
  /// purchase restored before that is simply "unavailable" until it does.
  final SupabaseClient? Function() _client;

  @override
  Future<VerifyOutcome> verify(String purchaseToken) async {
    final SupabaseClient? client = _client();
    if (client == null || client.auth.currentSession == null) {
      return VerifyOutcome.unavailable;
    }
    try {
      final FunctionResponse response = await client.functions.invoke(
        'verify-purchase',
        body: <String, dynamic>{
          'purchase_token': purchaseToken,
          'product_id': BillingConfig.removeAdsProductId,
        },
      );
      final Object? data = response.data;
      if (data is Map && data['premium'] is bool) {
        return data['premium'] == true
            ? VerifyOutcome.granted
            : VerifyOutcome.denied;
      }
      return VerifyOutcome.unavailable;
    } on Object catch (error) {
      AppLogger.debug('Purchase verification failed: $error', name: 'billing');
      return VerifyOutcome.unavailable;
    }
  }
}
