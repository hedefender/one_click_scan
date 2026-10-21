import '../../core/errors/app_exceptions.dart';

/// Adds a copy of an image to the phone Gallery.
abstract interface class GalleryService {
  /// Saves the image at [path] under the name [fileName] (with extension).
  /// Asks for the Gallery permission only now, when a copy is really
  /// requested. Throws `GalleryException` on failure.
  Future<void> saveImage(String path, {required String fileName});
}

/// Used on platforms without an implementation, and as the container default.
class UnsupportedGalleryService implements GalleryService {
  const UnsupportedGalleryService();

  @override
  Future<void> saveImage(String path, {required String fileName}) {
    throw const GalleryException('Gallery is not supported on this platform');
  }
}
