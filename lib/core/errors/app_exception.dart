/// Base class for every error the app throws on purpose.
///
/// Plugin/platform errors are caught at the boundary (services) and mapped to
/// one of these, so the presentation layer never has to know about
/// `PlatformException`, `BillingResponse` or AdMob error codes.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() =>
      '$runtimeType: $message${cause == null ? '' : ' ($cause)'}';
}

/// No connectivity, timeout, or the remote side is unreachable.
final class NetworkException extends AppException {
  const NetworkException(super.message, {super.cause});
}

/// A platform service (store, permission, ad SDK) is unavailable or refused.
final class PlatformServiceException extends AppException {
  const PlatformServiceException(super.message, {super.cause});
}

/// Local storage failed to read or write.
final class StorageException extends AppException {
  const StorageException(super.message, {super.cause});
}

/// A bundled or remote data source is missing or malformed.
final class DataException extends AppException {
  const DataException(super.message, {super.cause});
}

/// The user cancelled a flow that had already started.
final class CancelledByUserException extends AppException {
  const CancelledByUserException([super.message = 'Cancelled by user']);
}

/// Anything that does not fit above. Log it and fix the mapping.
final class UnknownException extends AppException {
  const UnknownException(super.message, {super.cause});
}
