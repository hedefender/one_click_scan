import 'package:flutter/services.dart';
import 'package:gal/gal.dart';

import '../../core/errors/app_exceptions.dart';
import '../../domain/ports/gallery_service.dart';

/// The Gallery copy, written by `ScanFilesHandler.kt` straight into MediaStore
/// (`Pictures/`), which gives back the URI of the entry. A discard deletes the
/// copy by that URI (ADR-027); the `gal` plugin could not give one.
///
/// `gal` is still used for one thing: the storage permission that Android 9 and
/// older need before a write (from Android 10 on `hasAccess` is true at once and
/// nothing is asked). It asks only here, when a copy is really requested.
class MediaStoreGalleryService implements GalleryService {
  MediaStoreGalleryService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Must match `CHANNEL` in ScanFilesHandler.kt.
  static const channelName = 'com.example.one_click_scan/scan_files';

  final MethodChannel _channel;

  @override
  Future<String> saveImage(String path, {required String fileName}) async {
    try {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
        throw const GalleryException('Gallery access was not granted');
      }
    } on GalException catch (error) {
      throw GalleryException(error.type.name);
    }
    final uri = await _invoke<String>('saveToGallery', <String, String>{
      'sourcePath': path,
      'fileName': fileName,
    });
    if (uri == null || uri.isEmpty) {
      throw const GalleryException('The Gallery returned no URI');
    }
    return uri;
  }

  @override
  Future<void> deleteImage(String uri) {
    return _invoke<void>('deleteGalleryItem', <String, String>{'uri': uri});
  }

  Future<T?> _invoke<T>(String method, Map<String, String> arguments) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      // The code only (no_access, write_failed, ...), never a path or a name.
      throw GalleryException(error.code);
    } on MissingPluginException {
      throw const GalleryException('no handler');
    }
  }
}
