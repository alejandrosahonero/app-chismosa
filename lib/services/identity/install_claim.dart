import 'dart:math';

import 'package:chismosa/core/utils/app_logger.dart';
import 'package:chismosa/services/backend/backend_providers.dart';
import 'package:chismosa/services/storage/key_value_store.dart';
import 'package:chismosa/services/storage/storage_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What the server said about this phone using the signed-in account.
enum ClaimResult {
  /// This phone may use it.
  ok,

  /// Another phone holds it and the account is not premium.
  moved,

  /// Could not ask (offline, server down, migration not run). Treated as
  /// allowed: a network problem must never lock anyone out of their account.
  unknown,
}

/// One phone at a time; several at once with premium (`0009_devices_premium`).
///
/// The phone is identified by a random install id kept in preferences, so an
/// Auto Backup reinstall keeps it and a new phone gets a new one.
class InstallClaim {
  InstallClaim(this._store, this._client);

  static const String _key = 'install_id';

  final KeyValueStore _store;
  final SupabaseClient? Function() _client;

  String get installId {
    final String? existing = _store.getString(_key);
    if (existing != null && existing.isNotEmpty) return existing;
    final String created = _uuidV4(Random.secure());
    _store.setString(_key, created);
    return created;
  }

  /// [take] brings the account to this phone; the phone that had it gets
  /// [ClaimResult.moved] the next time it asks.
  Future<ClaimResult> claim({bool take = false}) async {
    final SupabaseClient? client = _client();
    if (client == null || client.auth.currentUser == null) {
      return ClaimResult.unknown;
    }
    try {
      final Object? result = await client.rpc<Object?>(
        'claim_install',
        params: <String, dynamic>{'p_install': installId, 'p_take': take},
      );
      return switch (result) {
        'ok' => ClaimResult.ok,
        'moved' => ClaimResult.moved,
        _ => ClaimResult.unknown,
      };
    } on Object catch (error) {
      AppLogger.debug('Install claim failed: $error', name: 'identity');
      return ClaimResult.unknown;
    }
  }

  static String _uuidV4(Random random) {
    final List<int> b = List<int>.generate(16, (_) => random.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final String hex = b
        .map((int x) => x.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

final Provider<InstallClaim> installClaimProvider = Provider<InstallClaim>(
  (Ref ref) => InstallClaim(
    ref.watch(keyValueStoreProvider),
    () => ref.read(supabaseClientProvider),
  ),
);

/// True while another phone holds this account: the router sends the app to
/// the "your account is on another phone" screen.
final NotifierProvider<AccountMoved, bool> accountMovedProvider =
    NotifierProvider<AccountMoved, bool>(AccountMoved.new);

class AccountMoved extends Notifier<bool> {
  @override
  bool build() => false;

  void set({required bool moved}) => state = moved;
}
