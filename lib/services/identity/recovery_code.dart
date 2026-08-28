import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// The one secret behind an anonymous account.
///
/// ## The problem it solves
///
/// Android deletes an app's private files on uninstall, so the plain reading of
/// "keep the account on the phone" does not exist. Auto Backup covers most
/// people silently, but it depends on the user having backup switched on and
/// signing in with the same Google account — a portion of users would lose
/// their threads with nothing to do about it. This is that portion's way out,
/// and the only way to move an account to a different phone.
///
/// ## How it works
///
/// One random secret is generated once. From it, deterministically:
///
/// * the **code** the user can write down, and
/// * the e-mail and password of the Supabase account.
///
/// The account starts as an anonymous sign-in and is immediately upgraded to
/// those credentials, so restoring is a normal password sign-in. The address is
/// on an unreachable domain and is never shown, sent or asked for: it exists
/// because a password needs an identifier, not because there is a mailbox.
///
/// Nothing here is reversible: the code cannot be recovered from the account,
/// only the other way round. Losing it means losing the account, which is the
/// honest trade for asking the user for nothing.
class RecoveryCode {
  const RecoveryCode(this.secret);

  /// [secretBytes] bytes of entropy, printed as [_groups] groups of
  /// [_groupSize] characters. 15 bytes is 120 bits: far beyond guessing, and
  /// short enough to fit on the back of a receipt.
  static const int secretBytes = 15;
  static const int _groupSize = 4;
  static const int _groups = 6;

  /// Crockford base32 without I, L, O and U: nothing in it can be confused with
  /// 1, 0 or read as a word by accident.
  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  static const String _prefix = 'CHM';

  /// The domain is deliberately unroutable. See the class doc: there is no
  /// mailbox and there must never be one, or a leak of the database becomes a
  /// list of addresses.
  static const String _emailDomain = 'chismosa.invalid';

  /// Raw secret, [secretBytes] long.
  final List<int> secret;

  /// Generates a fresh secret from the platform's cryptographic RNG.
  factory RecoveryCode.generate([Random? random]) {
    final Random rng = random ?? Random.secure();
    return RecoveryCode(
      List<int>.generate(secretBytes, (_) => rng.nextInt(256), growable: false),
    );
  }

  /// Parses a code the user typed. Case, spaces and dashes are ignored, so
  /// "chm 4f7k..." and "CHM-4F7K-..." are the same code.
  ///
  /// Returns null when the text is not a code at all — the caller shows "ese
  /// código no vale", never a parse error.
  static RecoveryCode? tryParse(String input) {
    final String cleaned = input.toUpperCase().replaceAll(
      RegExp('[^0-9A-Z]'),
      '',
    );
    final String body = cleaned.startsWith(_prefix)
        ? cleaned.substring(_prefix.length)
        : cleaned;

    if (body.length != _groupSize * _groups) return null;

    int accumulator = 0;
    int bits = 0;
    final List<int> bytes = <int>[];
    for (int i = 0; i < body.length; i++) {
      final int value = _alphabet.indexOf(body[i]);
      if (value < 0) return null;
      accumulator = (accumulator << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        bytes.add((accumulator >> bits) & 0xFF);
      }
    }
    if (bytes.length != secretBytes) return null;
    return RecoveryCode(bytes);
  }

  /// Restores a secret persisted on disk.
  static RecoveryCode? tryDecodeStored(String stored) {
    try {
      final List<int> bytes = base64Url.decode(stored);
      if (bytes.length != secretBytes) return null;
      return RecoveryCode(bytes);
    } on FormatException {
      return null;
    }
  }

  /// How the secret is written to disk. Not the printable code: parsing that
  /// back would be a second thing that has to stay correct forever.
  String encodeForStorage() => base64Url.encode(secret);

  /// The code as the user sees it: `CHM-4F7K-9QW2-...`.
  String get formatted {
    int accumulator = 0;
    int bits = 0;
    final StringBuffer body = StringBuffer();
    for (final int byte in secret) {
      accumulator = (accumulator << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        body.write(_alphabet[(accumulator >> bits) & 0x1F]);
      }
    }
    if (bits > 0) {
      body.write(_alphabet[(accumulator << (5 - bits)) & 0x1F]);
    }

    final String chars = body.toString();
    final List<String> groups = <String>[_prefix];
    for (int i = 0; i < chars.length; i += _groupSize) {
      groups.add(chars.substring(i, min(i + _groupSize, chars.length)));
    }
    return groups.join('-');
  }

  /// Account identifier. Derived, never stored, never shown.
  String get email {
    final String digest = sha256
        .convert(<int>[...secret, ..._salt('email')])
        .toString()
        .substring(0, 32);
    return 'u$digest@$_emailDomain';
  }

  /// Account password. A 256 bit digest, so the account is only as guessable as
  /// the code itself.
  String get password =>
      base64Url.encode(sha256.convert(<int>[...secret, ..._salt('pw')]).bytes);

  /// Domain separation: without it the e-mail would be a hash of the same
  /// preimage as the password, and publishing one would leak the other.
  static List<int> _salt(String purpose) => utf8.encode('chismosa:$purpose');

  @override
  bool operator ==(Object other) =>
      other is RecoveryCode &&
      other.secret.length == secret.length &&
      _constantTimeEquals(other.secret, secret);

  @override
  int get hashCode => Object.hashAll(secret);

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Never let a secret reach a log.
  @override
  String toString() => 'RecoveryCode(hidden)';
}
