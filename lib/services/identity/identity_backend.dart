import 'package:chismosa/services/identity/captcha/turnstile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The auth operations `AnonymousIdentityService` needs.
///
/// Narrow on purpose: the flow around it (when to create, when to restore, what
/// to do when a restore fails) is the part with decisions in it, and it has to
/// be testable without a network or a project.
abstract interface class IdentityBackend {
  /// Id of the signed-in account, or null.
  String? get currentUserId;

  /// Whether the session is still a bare anonymous one, i.e. has no credentials
  /// attached and therefore cannot be restored anywhere.
  bool get isUpgraded;

  Future<String> signInAnonymously();

  /// Attaches credentials derived from the recovery code to the current
  /// account, turning it into something that can be signed back into.
  Future<void> attachCredentials({
    required String email,
    required String password,
  });

  Future<String> signInWithCredentials({
    required String email,
    required String password,
  });

  /// Deletes the signed-in account and everything it wrote, on the server,
  /// and drops the local session.
  Future<void> deleteAccount();
}

class SupabaseIdentityBackend implements IdentityBackend {
  SupabaseIdentityBackend(this._client, {this.captcha});

  final SupabaseClient _client;

  /// Null while CAPTCHA is not configured (see `turnstile.dart`). When set,
  /// every call that can create or open an account carries a fresh token.
  final CaptchaTokenSource? captcha;

  GoTrueClient get _auth => _client.auth;

  @override
  String? get currentUserId => _auth.currentUser?.id;

  @override
  bool get isUpgraded => _auth.currentUser?.email?.isNotEmpty ?? false;

  @override
  Future<String> signInAnonymously() async {
    final AuthResponse response = await _auth.signInAnonymously(
      captchaToken: await captcha?.call(),
    );
    final String? id = response.user?.id;
    if (id == null) {
      throw const AuthException('Anonymous sign-in returned no user');
    }
    return id;
  }

  @override
  Future<void> attachCredentials({
    required String email,
    required String password,
  }) async {
    await _auth.updateUser(UserAttributes(email: email, password: password));
  }

  @override
  Future<String> signInWithCredentials({
    required String email,
    required String password,
  }) async {
    final AuthResponse response = await _auth.signInWithPassword(
      email: email,
      password: password,
      captchaToken: await captcha?.call(),
    );
    final String? id = response.user?.id;
    if (id == null) {
      throw const AuthException('Sign-in returned no user');
    }
    return id;
  }

  @override
  Future<void> deleteAccount() async {
    // delete_my_account() (0010) removes auth.users; everything else cascades.
    await _client.rpc<void>('delete_my_account');
    try {
      await _auth.signOut(scope: SignOutScope.local);
    } on Object {
      // The session belonged to an account that no longer exists: the server
      // may refuse to sign it out. Locally it is gone either way.
    }
  }
}
