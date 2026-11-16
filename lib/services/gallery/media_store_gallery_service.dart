import 'package:flutter/services.dart';

import '../../core/errors/app_exceptions.dart';
import '../../domain/ports/gallery_service.dart';

/// The Gallery copy, written by `ScanFilesHandler.kt` straight into MediaStore
/// (`Pictures/`), which gives back the URI of the entry. A discard deletes the
/// copy by that URI (ADR-027); the `gal` plugin could not give one.
///
/// The app needs Android 10 or newer (minSdk 29, ADR-035), where an app writes
/// and deletes its own MediaStore entries with no storage permission, so nothing
/// is asked here. (The `gal` plugin only asked for that permission on Android 9
/// and older and was removed.)
class MediaStoreGalleryService implements GalleryService {
  MediaStoreGalleryService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Must match `CHANNEL` in ScanFilesHandler.kt.
  static const channelName = 'io.github.hedefender.simpledocscan/scan_files';

  final MethodChannel _channel;

  @override
  Future<String> saveImage(String path, {required String fileName}) async {
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
