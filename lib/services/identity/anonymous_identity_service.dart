import 'package:chismosa/core/utils/app_logger.dart';
import 'package:chismosa/services/identity/identity_backend.dart';
import 'package:chismosa/services/identity/recovery_code.dart';
import 'package:chismosa/services/identity/secret_store.dart';

/// The signed-in anonymous account.
class AnonymousIdentity {
  const AnonymousIdentity({required this.userId, required this.code});

  final String userId;

  /// Shown once in Settings under "guarda este código". Held in memory only.
  final RecoveryCode code;
}

/// Creates and restores the one anonymous account this app has.
///
/// There is no sign-up, no e-mail and no password the user ever sees: opening
/// the app for the first time creates an account, and a recovery code is the
/// only thing that can bring it back on another phone or after a reinstall that
/// Auto Backup did not cover.
///
/// See [RecoveryCode] for why an account has credentials at all.
class AnonymousIdentityService {
  AnonymousIdentityService({required this.backend, required this.store});

  final IdentityBackend backend;
  final SecretStore store;

  AnonymousIdentity? _identity;
  AnonymousIdentity? get identity => _identity;

  /// Signs the user in, creating the account the first time.
  ///
  /// Order matters. A restored install has the secret file but no session, and
  /// an ordinary launch has both, so the stored secret is consulted before
  /// anything is created — otherwise a reinstall would silently start a second
  /// account and the first one's threads would be unreachable forever.
  Future<AnonymousIdentity> ensureSignedIn() async {
    final AnonymousIdentity? existing = _identity;
    if (existing != null) return existing;

    final String? stored = await store.read();
    final RecoveryCode? storedCode = stored == null
        ? null
        : RecoveryCode.tryDecodeStored(stored);

    // Live session: the common case, every launch after the first.
    final String? currentId = backend.currentUserId;
    if (currentId != null && storedCode != null && backend.isUpgraded) {
      return _remember(currentId, storedCode);
    }

    // Session survived but the account was never given credentials (the app was
    // killed between the two calls below). Finish the job now rather than leave
    // an account that can never be recovered.
    if (currentId != null && !backend.isUpgraded) {
      return _attach(currentId, storedCode ?? RecoveryCode.generate());
    }

    // Reinstall restored by Auto Backup: the file is here, the session is not.
    if (storedCode != null) {
      try {
        final String id = await backend.signInWithCredentials(
          email: storedCode.email,
          password: storedCode.password,
        );
        return _remember(id, storedCode);
      } on Object catch (error, stack) {
        // The secret no longer matches an account — deleted, or a project that
        // was wiped in development. Falling through to a new account is the
        // only thing that keeps the app usable.
        AppLogger.error(
          'Stored recovery secret did not sign in; creating a new account',
          name: 'identity',
          error: error,
          stackTrace: stack,
        );
      }
    }

    final String id = await backend.signInAnonymously();
    return _attach(id, RecoveryCode.generate());
  }

  /// Restores an account from a code the user typed on another phone.
  ///
  /// Overwrites the local secret on success only: a failed attempt must not
  /// cost the user the account they already had on this device.
  Future<AnonymousIdentity> restoreFromCode(String input) async {
    final RecoveryCode? code = RecoveryCode.tryParse(input);
    if (code == null) {
      throw const InvalidRecoveryCodeException();
    }

    final String id = await backend.signInWithCredentials(
      email: code.email,
      password: code.password,
    );
    await store.write(code.encodeForStorage());
    return _remember(id, code);
  }

  /// Deletes the account on the server and starts a new, empty one here.
  ///
  /// The local secret is cleared only after the server confirmed the deletion:
  /// a failed attempt keeps the account and its code exactly as they were.
  Future<AnonymousIdentity> deleteAccount() async {
    await backend.deleteAccount();
    await store.clear();
    _identity = null;
    final String id = await backend.signInAnonymously();
    return _attach(id, RecoveryCode.generate());
  }

  Future<AnonymousIdentity> _attach(String userId, RecoveryCode code) async {
    await backend.attachCredentials(email: code.email, password: code.password);
    await store.write(code.encodeForStorage());
    return _remember(userId, code);
  }

  AnonymousIdentity _remember(String userId, RecoveryCode code) =>
      _identity = AnonymousIdentity(userId: userId, code: code);
}

class InvalidRecoveryCodeException implements Exception {
  const InvalidRecoveryCodeException();
}
