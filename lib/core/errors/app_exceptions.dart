/// Thrown when the user-visible storage folder cannot be chosen or used.
class StorageFolderException implements Exception {
  const StorageFolderException(this.message);

  final String message;

  @override
  String toString() => 'StorageFolderException: $message';
}

enum ScanStoreFailure { noAccess, exists, writeFailed, sourceMissing, unknown }

/// Thrown when a file cannot be written to, listed in or deleted from the
/// user's folder. Carries a machine readable [failure], never file content.
class ScanStoreException implements Exception {
  const ScanStoreException(this.failure, [this.message = '']);

  final ScanStoreFailure failure;
  final String message;

  @override
  String toString() => 'ScanStoreException: ${failure.name} $message';
}

/// Thrown when a photo could not be taken.
class CameraCaptureException implements Exception {
  const CameraCaptureException([this.message = '']);

  final String message;

  @override
  String toString() => 'CameraCaptureException: $message';
}

/// Thrown when the Gallery copy fails (no permission or write error).
class GalleryException implements Exception {
  const GalleryException([this.message = '']);

  final String message;

  @override
  String toString() => 'GalleryException: $message';
}
