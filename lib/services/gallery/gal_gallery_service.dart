import 'dart:io';

import 'package:gal/gal.dart';

import '../../core/errors/app_exceptions.dart';
import '../../domain/ports/gallery_service.dart';

/// `gal` plugin implementation. On Android 10+ saving needs no permission;
/// on older versions `gal` asks for the storage permission, and only here,
/// when a copy is really requested.
///
/// `gal` names the Gallery copy after the file it is given, so the picture is
/// first copied under the wanted name into [workDirectory] (in the app cache)
/// and removed again afterwards. Leftovers of a killed run are removed at
/// start-up (see `IoScanTempStore.alsoPurge`).
class GalGalleryService implements GalleryService {
  const GalGalleryService({required this.workDirectory});

  final Directory workDirectory;

  @override
  Future<void> saveImage(String path, {required String fileName}) async {
    File? named;
    try {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        throw const GalleryException('Gallery access was not granted');
      }
      await workDirectory.create(recursive: true);
      named = await File(path)
          .copy('${workDirectory.path}${Platform.pathSeparator}$fileName');
      await Gal.putImage(named.path);
    } on GalException catch (error) {
      throw GalleryException(error.type.name);
    } on FileSystemException {
      throw const GalleryException('Could not prepare the Gallery copy');
    } finally {
      try {
        if (named != null && await named.exists()) await named.delete();
      } on FileSystemException {
        // Best effort: purged at the next start.
      }
    }
  }
}
