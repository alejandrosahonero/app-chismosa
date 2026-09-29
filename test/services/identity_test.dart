import 'dart:math';

import 'package:chismosa/services/identity/anonymous_identity_service.dart';
import 'package:chismosa/services/identity/identity_backend.dart';
import 'package:chismosa/services/identity/recovery_code.dart';
import 'package:chismosa/services/identity/secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deterministic bytes, so a failing expectation names a value instead of a
/// different random one on every run.
Random _seeded() => Random(42);

class _MemoryStore implements SecretStore {
  String? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String v) async => value = v;
}

class _FakeBackend implements IdentityBackend {
  _FakeBackend({this.existingAccounts = const <String, String>{}});

  /// email -> password, for accounts that already exist on the server.
  final Map<String, String> existingAccounts;

  String? currentId;
  bool upgraded = false;
  int anonymousSignIns = 0;
  int credentialSignIns = 0;
  String? attachedEmail;
  int deletions = 0;
  bool failDelete = false;

  @override
  String? get currentUserId => currentId;

  @override
  bool get isUpgraded => upgraded;

  @override
  Future<String> signInAnonymously() async {
    anonymousSignIns++;
    upgraded = false;
    return currentId = 'user-$anonymousSignIns';
  }

  @override
  Future<void> attachCredentials({
    required String email,
    required String password,
  }) async {
    attachedEmail = email;
    upgraded = true;
  }

  @override
  Future<String> signInWithCredentials({
    required String email,
    required String password,
  }) async {
    credentialSignIns++;
    if (existingAccounts[email] != password) {
      throw StateError('no such account');
    }
    upgraded = true;
    return currentId = 'restored';
  }

  @override
  Future<void> deleteAccount() async {
    if (failDelete) throw StateError('offline');
    deletions++;
    currentId = null;
    upgraded = false;
  }
}

void main() {
  group('RecoveryCode', () {
    test('a formatted code parses back to the same secret', () {
      final RecoveryCode code = RecoveryCode.generate(_seeded());
      expect(RecoveryCode.tryParse(code.formatted), code);
    });

    test('parsing ignores case, spaces and dashes', () {
      final RecoveryCode code = RecoveryCode.generate(_seeded());
      final String messy = code.formatted
          .toLowerCase()
          .replaceAll('-', ' ')
          .replaceAll(' ', '  ');
      expect(RecoveryCode.tryParse(messy), code);
    });

    test('a code of the wrong length is rejected rather than truncated', () {
      final RecoveryCode code = RecoveryCode.generate(_seeded());
      final String truncated = code.formatted.substring(
        0,
        code.formatted.length - 2,
      );
      expect(RecoveryCode.tryParse(truncated), isNull);
      expect(RecoveryCode.tryParse(''), isNull);
      expect(RecoveryCode.tryParse('not a code at all'), isNull);
    });

    test('the alphabet excludes the characters that get misread', () {
      final RecoveryCode code = RecoveryCode.generate(_seeded());
      expect(code.formatted, isNot(matches(RegExp('[ILOU]'))));
    });

    test('storage encoding round-trips', () {
      final RecoveryCode code = RecoveryCode.generate(_seeded());
      expect(RecoveryCode.tryDecodeStored(code.encodeForStorage()), code);
      expect(RecoveryCode.tryDecodeStored('not base64 %%%'), isNull);
      expect(RecoveryCode.tryDecodeStored(''), isNull);
    });

    test('e-mail and password are different derivations of one secret', () {
      final RecoveryCode code = RecoveryCode.generate(_seeded());
      // Domain separation: publishing one must not reveal the other.
      expect(code.email, isNot(contains(code.password)));
      expect(code.email, endsWith('@chismosa.invalid'));
      expect(code.password.length, greaterThan(32));
    });

    test('two secrets never derive the same account', () {
      final RecoveryCode a = RecoveryCode.generate();
      final RecoveryCode b = RecoveryCode.generate();
      expect(a.email, isNot(b.email));
    });

    test('the secret never reaches a log line', () {
      expect(
        RecoveryCode.generate(_seeded()).toString(),
        'RecoveryCode(hidden)',
      );
    });
  });

  group('AnonymousIdentityService', () {
    test('the first launch creates an account and stores its secret', () async {
      final _FakeBackend backend = _FakeBackend();
      final _MemoryStore store = _MemoryStore();
      final AnonymousIdentityService service = AnonymousIdentityService(
        backend: backend,
        store: store,
      );

      final AnonymousIdentity identity = await service.ensureSignedIn();

      expect(backend.anonymousSignIns, 1);
      expect(identity.userId, 'user-1');
      // Credentials are attached immediately: an account without them could
      // never be recovered anywhere.
      expect(backend.attachedEmail, identity.code.email);
      expect(store.value, identity.code.encodeForStorage());
    });

    test(
      'a later launch reuses the session without signing in again',
      () async {
        final _FakeBackend backend = _FakeBackend()
          ..currentId = 'user-1'
          ..upgraded = true;
        final RecoveryCode code = RecoveryCode.generate(_seeded());
        final _MemoryStore store = _MemoryStore()
          ..value = code.encodeForStorage();

        final AnonymousIdentity identity = await AnonymousIdentityService(
          backend: backend,
          store: store,
        ).ensureSignedIn();

        expect(identity.userId, 'user-1');
        expect(backend.anonymousSignIns, 0);
        expect(backend.credentialSignIns, 0);
      },
    );

    test(
      'a reinstall restored by Auto Backup signs back into the same account',
      () async {
        final RecoveryCode code = RecoveryCode.generate(_seeded());
        final _FakeBackend backend = _FakeBackend(
          existingAccounts: <String, String>{code.email: code.password},
        );
        final _MemoryStore store = _MemoryStore()
          ..value = code.encodeForStorage();

        final AnonymousIdentity identity = await AnonymousIdentityService(
          backend: backend,
          store: store,
        ).ensureSignedIn();

        expect(identity.userId, 'restored');
        // The whole point: no second account was created behind the user's back.
        expect(backend.anonymousSignIns, 0);
      },
    );

    test(
      'a stored secret that no longer matches falls back to a new account',
      () async {
        final RecoveryCode stale = RecoveryCode.generate(_seeded());
        final _FakeBackend backend = _FakeBackend();
        final _MemoryStore store = _MemoryStore()
          ..value = stale.encodeForStorage();

        final AnonymousIdentity identity = await AnonymousIdentityService(
          backend: backend,
          store: store,
        ).ensureSignedIn();

        expect(backend.credentialSignIns, 1);
        expect(backend.anonymousSignIns, 1);
        expect(store.value, identity.code.encodeForStorage());
      },
    );

    test(
      'a session that never got credentials is repaired, not replaced',
      () async {
        // The app was killed between signInAnonymously and attachCredentials.
        final _FakeBackend backend = _FakeBackend()
          ..currentId = 'user-1'
          ..upgraded = false;
        final _MemoryStore store = _MemoryStore();

        final AnonymousIdentity identity = await AnonymousIdentityService(
          backend: backend,
          store: store,
        ).ensureSignedIn();

        expect(identity.userId, 'user-1');
        expect(backend.anonymousSignIns, 0);
        expect(backend.attachedEmail, identity.code.email);
      },
    );

    test('restoring from a typed code adopts that account', () async {
      final RecoveryCode code = RecoveryCode.generate(_seeded());
      final _FakeBackend backend = _FakeBackend(
        existingAccounts: <String, String>{code.email: code.password},
      );
      final _MemoryStore store = _MemoryStore()..value = 'previous-secret';

      final AnonymousIdentity identity = await AnonymousIdentityService(
        backend: backend,
        store: store,
      ).restoreFromCode(code.formatted);

      expect(identity.userId, 'restored');
      expect(store.value, code.encodeForStorage());
    });

    test(
      'a wrong code leaves the account already on this device alone',
      () async {
        final _FakeBackend backend = _FakeBackend();
        final _MemoryStore store = _MemoryStore()..value = 'previous-secret';
        final AnonymousIdentityService service = AnonymousIdentityService(
          backend: backend,
          store: store,
        );

        await expectLater(
          service.restoreFromCode('CHM-XXXX'),
          throwsA(isA<InvalidRecoveryCodeException>()),
        );
        // A failed attempt that overwrote the secret would destroy the account
        // the user still has.
        expect(store.value, 'previous-secret');
      },
    );

    test(
      'a code that parses but does not exist also leaves the secret alone',
      () async {
        final RecoveryCode unknown = RecoveryCode.generate(_seeded());
        final _FakeBackend backend = _FakeBackend();
        final _MemoryStore store = _MemoryStore()..value = 'previous-secret';

        await expectLater(
          AnonymousIdentityService(
            backend: backend,
            store: store,
          ).restoreFromCode(unknown.formatted),
          throwsA(isA<StateError>()),
        );
        expect(store.value, 'previous-secret');
      },
    );

    test(
      'a refused restore signs back into the previous account and keeps it',
      () async {
        final RecoveryCode other = RecoveryCode.generate(_seeded());
        final Map<String, String> accounts = <String, String>{
          other.email: other.password,
        };
        final _FakeBackend backend = _FakeBackend(existingAccounts: accounts);
        final _MemoryStore store = _MemoryStore();
        final AnonymousIdentityService service = AnonymousIdentityService(
          backend: backend,
          store: store,
        );
        final AnonymousIdentity mine = await service.ensureSignedIn();
        accounts[mine.code.email] = mine.code.password;
        final String? mySecret = store.value;

        await expectLater(
          service.restoreFromCode(other.formatted, admit: () async => false),
          throwsA(isA<RestoreNotAdmittedException>()),
        );

        expect(store.value, mySecret);
        expect(service.identity?.code.email, mine.code.email);
        // One sign-in into the other account, one back into this one.
        expect(backend.credentialSignIns, 2);
      },
    );

    test('an admitted restore adopts the account', () async {
      final RecoveryCode code = RecoveryCode.generate(_seeded());
      final _FakeBackend backend = _FakeBackend(
        existingAccounts: <String, String>{code.email: code.password},
      );
      final _MemoryStore store = _MemoryStore();

      final AnonymousIdentity identity = await AnonymousIdentityService(
        backend: backend,
        store: store,
      ).restoreFromCode(code.formatted, admit: () async => true);

      expect(identity.userId, 'restored');
      expect(store.value, code.encodeForStorage());
    });

    test('deleting the account starts a new one with a new code', () async {
      final _FakeBackend backend = _FakeBackend();
      final _MemoryStore store = _MemoryStore();
      final AnonymousIdentityService service = AnonymousIdentityService(
        backend: backend,
        store: store,
      );
      final AnonymousIdentity before = await service.ensureSignedIn();

      final AnonymousIdentity after = await service.deleteAccount();

      expect(backend.deletions, 1);
      expect(after.userId, isNot(before.userId));
      expect(after.code, isNot(before.code));
      // The old code must not survive: it points at an account that is gone.
      expect(store.value, after.code.encodeForStorage());
      expect(service.identity, same(after));
    });

    test('a failed deletion keeps the account and its code', () async {
      final _FakeBackend backend = _FakeBackend();
      final _MemoryStore store = _MemoryStore();
      final AnonymousIdentityService service = AnonymousIdentityService(
        backend: backend,
        store: store,
      );
      final AnonymousIdentity before = await service.ensureSignedIn();
      backend.failDelete = true;

      await expectLater(service.deleteAccount(), throwsA(isA<StateError>()));

      expect(store.value, before.code.encodeForStorage());
      expect(service.identity, same(before));
      expect(backend.anonymousSignIns, 1);
    });
  });
}
