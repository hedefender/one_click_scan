import 'package:gal/gal.dart';

import '../../core/errors/app_exceptions.dart';
import '../../domain/ports/gallery_service.dart';

/// `gal` plugin implementation. On Android 10+ saving needs no permission;
/// on older versions `gal` asks for the storage permission, and only here,
/// when a copy is really requested.
class GalGalleryService implements GalleryService {
  const GalGalleryService();

  @override
  Future<void> saveImage(String path) async {
    try {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        throw const GalleryException('Gallery access was not granted');
      }
      await Gal.putImage(path);
    } on GalException catch (error) {
      throw GalleryException(error.type.name);
    }
  }
}
