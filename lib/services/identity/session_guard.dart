import 'dart:async';

import 'package:chismosa/core/utils/app_logger.dart';
import 'package:chismosa/services/backend/backend_providers.dart';
import 'package:chismosa/services/identity/anonymous_identity_service.dart';
import 'package:chismosa/services/identity/install_claim.dart';
import 'package:chismosa/services/push/push_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the app on an account that exists.
///
/// The rule: **if the account was deleted, it is gone, and a new one starts at
/// once.** Never a screen stuck on "check your connection" while every retry
/// sends the same dead session again.
///
/// Called from three places, so whichever notices first fixes it:
///   * startup (`bootstrap`), after signing in;
///   * the auth SDK signing the device out on its own (its refresh token was
///     rejected because the account or session no longer exists);
///   * any retry button, before it reloads.
class SessionGuard {
  SessionGuard(this._ref);

  final Ref _ref;

  /// Returns true when the account changed. Everything built on the old one
  /// (deck, threads, groups, premium) is then rebuilt via `sessionEpoch`, and
  /// push and the install claim follow the new account.
  Future<bool> ensureAlive() async {
    final AnonymousIdentityService? identity = _ref.read(
      identityServiceProvider,
    );
    if (identity == null) return false;
    try {
      final bool changed = await identity.ensureLiveAccount();
      if (changed) _afterAccountChange();
      return changed;
    } on Object catch (error) {
      // Offline or the server is down: the retry that follows shows the
      // ordinary offline state, and the next attempt tries again.
      AppLogger.debug('Session check failed: $error', name: 'identity');
      return false;
    }
  }

  void _afterAccountChange() {
    _ref.read(sessionEpochProvider.notifier).bump();
    final SupabaseClient? client = _ref.read(supabaseClientProvider);
    if (client != null) {
      unawaited(_ref.read(pushServiceProvider).attach(client));
    }
    unawaited(_ref.read(installClaimProvider).claim());
  }
}

final Provider<SessionGuard> sessionGuardProvider = Provider<SessionGuard>(
  SessionGuard.new,
);
