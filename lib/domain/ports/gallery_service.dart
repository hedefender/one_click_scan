import '../../core/errors/app_exceptions.dart';

/// Adds a copy of an image to the phone Gallery.
abstract interface class GalleryService {
  /// Saves the image at [path] under the name [fileName] (with extension) and
  /// returns the URI of the Gallery entry. Asks for the Gallery permission
  /// only now, when a copy is really requested. Throws `GalleryException` on
  /// failure.
  Future<String> saveImage(String path, {required String fileName});

  /// Deletes a Gallery entry that [saveImage] returned (only that one, by its
  /// URI). Does nothing when it is already gone; throws `GalleryException` when
  /// it is still there and could not be deleted.
  Future<void> deleteImage(String uri);
}

/// Used on platforms without an implementation, and as the container default.
class UnsupportedGalleryService implements GalleryService {
  const UnsupportedGalleryService();

  @override
  Future<String> saveImage(String path, {required String fileName}) {
    throw const GalleryException('Gallery is not supported on this platform');
  }

  @override
  Future<void> deleteImage(String uri) {
    throw const GalleryException('Gallery is not supported on this platform');
  }
}
