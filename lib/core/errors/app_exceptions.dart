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

/// The user stopped the storing of the pictures. What was written is already
/// rolled back when this is thrown (Phase 5.1, ADR-028).
class ScanStoreCancelled implements Exception {
  const ScanStoreCancelled();

  @override
  String toString() => 'ScanStoreCancelled';
}

/// Why the PDF of a scan could not be made or stored. The photos are stored
/// before the PDF, so none of these loses a photo.
enum ScanPdfFailure {
  /// A page has no picture: its working copy could not be made (unreadable or
  /// too large photo).
  pageImageMissing,

  /// The platform has no PDF writer.
  unsupported,

  /// The writer failed.
  buildFailed,

  /// The user's folder is no longer accessible.
  noAccess,

  /// The PDF could not be written into `./pdf`.
  writeFailed,
}

/// Thrown by the PDF layer. Carries a machine readable [failure], never
/// content of the document.
class ScanPdfException implements Exception {
  const ScanPdfException(this.failure, [this.message = '']);

  final ScanPdfFailure failure;
  final String message;

  @override
  String toString() => 'ScanPdfException: ${failure.name} $message';
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
