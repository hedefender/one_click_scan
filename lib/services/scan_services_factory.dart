import 'dart:io' show Directory, Platform;

import 'package:path_provider/path_provider.dart';

import 'camera/camera_service.dart';
import 'camera/plugin_camera_service.dart';
import 'camera/unsupported_camera_service.dart';
import 'gallery/media_store_gallery_service.dart';
import '../domain/ports/gallery_service.dart';
import 'scan_files/android_scan_file_store.dart';
import 'scan_files/io_scan_temp_store.dart';
import '../domain/ports/scan_file_store.dart';
import 'scan_files/scan_temp_store.dart';
import 'scan_files/unsupported_scan_file_store.dart';

/// The platform adapters of the scan flow, created together because the
/// camera and the temp store share the same cache directory.
class ScanServices {
  const ScanServices({
    required this.camera,
    required this.fileStore,
    required this.gallery,
    required this.tempStore,
  });

  final CameraService camera;
  final ScanFileStore fileStore;
  final GalleryService gallery;
  final ScanTempStore tempStore;
}

Future<ScanServices> createPlatformScanServices() async {
  if (!Platform.isAndroid) {
    return const ScanServices(
      camera: UnsupportedCameraService(),
      fileStore: UnsupportedScanFileStore(),
      gallery: UnsupportedGalleryService(),
      tempStore: NoopScanTempStore(),
    );
  }
  final cache = await getTemporaryDirectory();
  final pages = Directory('${cache.path}${Platform.pathSeparator}scan_pages');
  final staleGalleryCopies = Directory(
    '${cache.path}${Platform.pathSeparator}gallery_copies',
  );
  return ScanServices(
    camera: PluginCameraService(cacheDirectory: pages),
    fileStore: AndroidScanFileStore(),
    gallery: MediaStoreGalleryService(),
    // Leftovers of the old copy-under-a-name step (before Phase 5).
    tempStore: IoScanTempStore(pages, alsoPurge: [staleGalleryCopies]),
  );
}
