import '../../core/errors/app_exceptions.dart';

/// Adds a copy of an image to the phone Gallery.
abstract interface class GalleryService {
  /// Saves the image at [path]. Asks for the Gallery permission only now,
  /// when a copy is really requested. Throws `GalleryException` on failure.
  Future<void> saveImage(String path);
}

/// Used on platforms without an implementation, and as the container default.
class UnsupportedGalleryService implements GalleryService {
  const UnsupportedGalleryService();

  @override
  Future<void> saveImage(String path) {
    throw const GalleryException('Gallery is not supported on this platform');
  }
}
