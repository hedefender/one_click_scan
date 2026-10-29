import '../../core/errors/app_exceptions.dart';
import '../../core/logging/app_logger.dart';
import '../ports/gallery_counter_store.dart';
import '../ports/gallery_service.dart';
import '../ports/scan_file_store.dart';
import '../entities/captured_page.dart';
import '../entities/storage_folder.dart';
import '../entities/stored_scan.dart';
import '../scan/gallery_naming.dart';
import '../scan/scan_flow.dart' show ScanFlowCancellation;
import '../scan/scan_naming.dart';

/// Copies the captured pages into `./pictures` of the user's folder and,
/// when asked, into the Gallery.
///
/// Writing to the folder is all or nothing: if one picture fails, the ones
/// already written are removed again and the error is rethrown, so a retry
/// starts clean and no half scan is left in the user's folder. A failing
/// Gallery copy never fails the scan; it is reported per picture.
///
/// A cancel (ADR-028) is treated like a failure: everything written so far, the
/// pictures and the Gallery copies, is deleted again by its recorded name or
/// URI and `ScanStoreCancelled` is thrown, so a stopped save leaves nothing.
class StoreScanPages {
  const StoreScanPages({
    required this.fileStore,
    required this.gallery,
    required this.naming,
    required this.galleryNaming,
    required this.galleryCounter,
    required this.logger,
  });

  static const picturesFolder = 'pictures';
  static const pdfFolder = 'pdf';
  static const _jpegMimeType = 'image/jpeg';

  final ScanFileStore fileStore;
  final GalleryService gallery;
  final ScanNaming naming;
  final GalleryNaming galleryNaming;
  final GalleryCounterStore galleryCounter;
  final AppLogger logger;

  /// Throws `ScanStoreException` when the folder cannot be written and
  /// `ScanStoreCancelled` when [cancellation] was cancelled (nothing is left).
  Future<StoredScan> call({
    required List<CapturedPage> pages,
    required StorageFolder folder,
    required bool saveToGallery,
    ScanFlowCancellation? cancellation,
  }) async {
    if (pages.isEmpty) {
      throw ArgumentError.value(pages, 'pages', 'must not be empty');
    }

    await fileStore.ensureSubfolder(folder, picturesFolder);
    await _hideFromMediaIndex(folder);
    // The stem is free in both folders, so the PDF that follows (named after
    // the same stem, ADR-005) can never meet a file that is already there.
    final existing = [
      ...await fileStore.listFileNames(folder, picturesFolder),
      ...await fileStore.listFileNames(folder, pdfFolder),
    ];
    final stem = naming.nextStem(naming.existingStems(existing));

    final ordered = [...pages]..sort((a, b) => a.order.compareTo(b.order));
    final written = <String>[];
    var pictures = <StoredPicture>[];
    try {
      for (var index = 0; index < ordered.length; index++) {
        if (cancellation?.isCancelled ?? false) {
          throw const ScanStoreCancelled();
        }
        final fileName = naming.pictureName(stem, index + 1);
        final uri = await fileStore.copyToFolder(
          folder: folder,
          subfolder: picturesFolder,
          fileName: fileName,
          mimeType: _jpegMimeType,
          sourcePath: ordered[index].path,
        );
        written.add(fileName);
        pictures.add(
          StoredPicture(
            fileName: fileName,
            sourcePath: ordered[index].path,
            uri: uri,
          ),
        );
      }
    } catch (_) {
      await _rollback(folder, written);
      rethrow;
    }
    if (cancellation?.isCancelled ?? false) {
      await _rollback(folder, written);
      throw const ScanStoreCancelled();
    }

    if (saveToGallery) {
      final copied = <StoredPicture>[];
      for (final picture in pictures) {
        if (cancellation?.isCancelled ?? false) {
          await _rollbackGallery(copied);
          await _rollback(folder, written);
          throw const ScanStoreCancelled();
        }
        copied.add(await _copyToGallery(picture));
      }
      pictures = copied;
    }
    if (cancellation?.isCancelled ?? false) {
      await _rollbackGallery(pictures);
      await _rollback(folder, written);
      throw const ScanStoreCancelled();
    }
    return StoredScan(stem: stem, pictures: pictures);
  }

  /// The `.nomedia` marker keeps the originals out of the Gallery, so the
  /// switch decides alone whether a copy shows up there. A failure is only
  /// logged: the scan itself is more important than the marker.
  Future<void> _hideFromMediaIndex(StorageFolder folder) async {
    try {
      await fileStore.ensureNoMedia(folder, picturesFolder);
    } on ScanStoreException catch (error, stackTrace) {
      logger.error('Could not hide the pictures folder', error, stackTrace);
    }
  }

  /// Each copy takes the next daily number, but only a saved copy uses it up:
  /// a failure leaves no gap, the next picture gets the same number.
  Future<StoredPicture> _copyToGallery(StoredPicture picture) async {
    final date = galleryNaming.today();
    final number = galleryCounter.nextNumber(date);
    final String galleryUri;
    try {
      galleryUri = await gallery.saveImage(
        picture.sourcePath,
        fileName: galleryNaming.fileName(date, number),
      );
    } catch (error, stackTrace) {
      logger.error('Gallery copy failed', error, stackTrace);
      return picture.copyWith(gallery: GalleryCopyStatus.failed);
    }
    try {
      await galleryCounter.markUsed(date, number);
    } catch (error, stackTrace) {
      logger.error('Gallery counter not saved', error, stackTrace);
    }
    return picture.copyWith(
      gallery: GalleryCopyStatus.saved,
      galleryUri: galleryUri,
    );
  }

  Future<void> _rollbackGallery(List<StoredPicture> pictures) async {
    for (final picture in pictures) {
      final uri = picture.galleryUri;
      if (picture.gallery != GalleryCopyStatus.saved || uri == null) continue;
      try {
        await gallery.deleteImage(uri);
      } catch (error, stackTrace) {
        logger.error('Rollback of a Gallery copy failed', error, stackTrace);
      }
    }
  }

  Future<void> _rollback(StorageFolder folder, List<String> written) async {
    for (final fileName in written) {
      try {
        await fileStore.deleteFile(
          folder: folder,
          subfolder: picturesFolder,
          fileName: fileName,
        );
      } on ScanStoreException catch (error, stackTrace) {
        logger.error('Rollback of a stored picture failed', error, stackTrace);
      }
    }
  }
}
