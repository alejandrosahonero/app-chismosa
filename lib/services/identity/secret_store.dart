import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where the recovery secret is kept between runs.
abstract interface class SecretStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

/// A plain file in the app's support directory.
///
/// **Deliberately not `flutter_secure_storage`.** On Android that writes to
/// EncryptedSharedPreferences, whose master key lives in the hardware keystore
/// and is *not* part of Auto Backup: a restored install gets the ciphertext and
/// no way to read it, which is worse than not having it — the account looks
/// present and is unusable. A plain file in the backed-up directory is what
/// actually survives a reinstall, which is the entire point of this secret.
///
/// The trade is real and worth stating: the secret sits unencrypted in app
/// storage, readable on a rooted device or by whoever holds an unlocked phone.
/// It protects an anonymous account with no name, no e-mail and no payment
/// information attached, and the alternative protects nothing at all because
/// the data never comes back.
class FileSecretStore implements SecretStore {
  FileSecretStore({this.directory});

  static const String _fileName = 'identity.key';

  /// Injected in tests; the real app resolves the support directory itself.
  final Directory? directory;
  File? _cached;

  Future<File> _file() async {
    final File? cached = _cached;
    if (cached != null) return cached;
    final Directory dir = directory ?? await getApplicationSupportDirectory();
    return _cached = File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  @override
  Future<String?> read() async {
    try {
      final File file = await _file();
      if (!file.existsSync()) return null;
      final String contents = (await file.readAsString()).trim();
      return contents.isEmpty ? null : contents;
    } on FileSystemException {
      // An unreadable key is the same situation as no key: a new account gets
      // created. Throwing here would leave the app with no way in at all.
      return null;
    }
  }

  @override
  Future<void> write(String value) async {
    final File file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(value, flush: true);
  }

  @override
  Future<void> clear() async {
    final File file = await _file();
    if (file.existsSync()) {
      await file.delete();
    }
  }
}
