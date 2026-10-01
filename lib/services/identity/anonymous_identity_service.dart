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

  /// Every operation that can switch accounts runs one at a time. A dead
  /// session is noticed from several places at once (startup, the SDK
  /// signing out, a retry button); without this they would each create an
  /// account.
  Future<void> _queue = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final Future<T> result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// Makes sure the account this device uses still exists on the server, and
  /// replaces it with a fresh one when it does not.
  ///
  /// An account can disappear under a running app: the nightly clean-ups
  /// (0013, 0015), "delete my account" on another device, a moderator. The
  /// session cached on the device then fails every request with a 401, and
  /// retrying the same request can never fix it. A deleted account is gone for
  /// good, so the only correct move is to start a new one, at once.
  ///
  /// Returns true when the account changed, so the caller can rebuild what was
  /// loaded with the old one. A network failure while checking is not proof of
  /// anything and changes nothing.
  Future<bool> ensureLiveAccount() => _serial(() async {
    final String? before = _identity?.userId ?? backend.currentUserId;
    if (backend.currentUserId != null) {
      if (await backend.checkSession() != false) {
        if (_identity != null) return false;
      } else {
        AppLogger.debug('Session is dead; starting over', name: 'identity');
        _identity = null;
        await backend.signOutLocally();
      }
    }
    final AnonymousIdentity now = await _signIn();
    return before != now.userId;
  });

  /// Signs the user in, creating the account the first time.
  ///
  /// Order matters. A restored install has the secret file but no session, and
  /// an ordinary launch has both, so the stored secret is consulted before
  /// anything is created — otherwise a reinstall would silently start a second
  /// account and the first one's threads would be unreachable forever.
  Future<AnonymousIdentity> ensureSignedIn() => _serial(_signIn);

  Future<AnonymousIdentity> _signIn() async {
    final AnonymousIdentity? existing = _identity;
    if (existing != null) return existing;

    final String? stored = await store.read();
    final RecoveryCode? storedCode = stored == null
        ? null
        : RecoveryCode.tryDecodeStored(stored);

    // Live session: the common case, every launch after the first. The session
    // is read from the device, so it is checked with the server once: when the
    // account was deleted meanwhile it is dropped here and a new account is
    // made below, instead of failing every request until the page is reloaded.
    String? currentId = backend.currentUserId;
    if (currentId != null && await backend.checkSession() == false) {
      AppLogger.debug('Stored session is dead; dropping it', name: 'identity');
      await backend.signOutLocally();
      currentId = null;
    }
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
      } on Object catch (error) {
        // Only a definite "no such account" starts over. A network error is
        // not one: creating a new account then would abandon the real one
        // for good, so it is rethrown and the next start tries again.
        if (!backend.isAccountGone(error)) rethrow;
        // Expected, not an error: the nightly clean-ups delete inactive and
        // empty accounts, and "delete my account" on another device does too.
        AppLogger.debug(
          'Stored account no longer exists; creating a new one',
          name: 'identity',
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
  Future<AnonymousIdentity> restoreFromCode(
    String input, {
    Future<bool> Function()? admit,
  }) => _serial(() => _restore(input, admit));

  Future<AnonymousIdentity> _restore(
    String input,
    Future<bool> Function()? admit,
  ) async {
    final RecoveryCode? code = RecoveryCode.tryParse(input);
    if (code == null) {
      throw const InvalidRecoveryCodeException();
    }

    final AnonymousIdentity? previous = _identity;
    final String id = await backend.signInWithCredentials(
      email: code.email,
      password: code.password,
    );

    // [admit] runs signed in as the restored account (only it can read its own
    // profile) and before its secret is stored. A refusal signs back into the
    // previous account, so nothing on this device changes. The web uses it to
    // let in Premium accounts only.
    if (admit != null && !await admit()) {
      if (previous != null) {
        await backend.signInWithCredentials(
          email: previous.code.email,
          password: previous.code.password,
        );
      }
      throw const RestoreNotAdmittedException();
    }

    await store.write(code.encodeForStorage());
    return _remember(id, code);
  }

  /// Deletes the account on the server and starts a new, empty one here.
  ///
  /// The local secret is cleared only after the server confirmed the deletion:
  /// a failed attempt keeps the account and its code exactly as they were.
  Future<AnonymousIdentity> deleteAccount() => _serial(_delete);

  Future<AnonymousIdentity> _delete() async {
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

/// The code was valid but the `admit` check of [AnonymousIdentityService
/// .restoreFromCode] refused the account (on the web: not Premium).
class RestoreNotAdmittedException implements Exception {
  const RestoreNotAdmittedException();
}
