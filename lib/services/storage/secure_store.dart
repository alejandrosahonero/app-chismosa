import 'package:aja/core/errors/app_exception.dart';
import 'package:aja/core/utils/app_logger.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted key-value storage for sensitive data (purchase tokens, premium
/// entitlement).
///
/// Reads never throw: a corrupted keystore entry (common after a restore from
/// backup on a different device) returns `null` so the caller degrades to
/// "not premium" and re-verifies against the store, instead of crashing at
/// startup.
class SecureStore {
  const SecureStore(this._storage);

  final FlutterSecureStorage _storage;

  static const AndroidOptions androidOptions = AndroidOptions(
    // Explicit namespace so the encrypted entries stay addressable even if the
    // `applicationId` ever changes.
    storageNamespace: 'aja_secure',
  );

  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key, aOptions: androidOptions);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'SecureStore read failed for "$key"',
        name: 'storage',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value, aOptions: androidOptions);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'SecureStore write failed for "$key"',
        name: 'storage',
        error: error,
        stackTrace: stackTrace,
      );
      throw StorageException('Could not persist "$key"', cause: error);
    }
  }

  Future<void> delete(String key) =>
      _storage.delete(key: key, aOptions: androidOptions);
}
