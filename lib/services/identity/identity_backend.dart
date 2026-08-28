import 'package:supabase_flutter/supabase_flutter.dart';

/// The four auth operations `AnonymousIdentityService` needs.
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
}

class SupabaseIdentityBackend implements IdentityBackend {
  SupabaseIdentityBackend(this._auth);

  final GoTrueClient _auth;

  @override
  String? get currentUserId => _auth.currentUser?.id;

  @override
  bool get isUpgraded => _auth.currentUser?.email?.isNotEmpty ?? false;

  @override
  Future<String> signInAnonymously() async {
    final AuthResponse response = await _auth.signInAnonymously();
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
    );
    final String? id = response.user?.id;
    if (id == null) {
      throw const AuthException('Sign-in returned no user');
    }
    return id;
  }
}
