import 'package:equatable/equatable.dart';

import '../../core/logging/app_logger.dart';
import '../entities/pdf_page_input.dart';
import '../entities/stored_scan.dart';
import '../ports/gallery_service.dart';
import '../ports/scan_file_store.dart';

/// What a discard left behind. Zero everywhere means the scan is gone.
class DiscardOutcome extends Equatable {
  const DiscardOutcome({
    this.picturesLeft = 0,
    this.pdfLeft = false,
    this.galleryLeft = 0,
  });

  /// Pictures in `./pictures` that could not be deleted.
  final int picturesLeft;

  /// The PDF in `./pdf` could not be deleted.
  final bool pdfLeft;

  /// Gallery copies that could not be deleted.
  final int galleryLeft;

  /// Nothing of the scan is left. Only then may the screen say it is deleted.
  bool get complete => picturesLeft == 0 && !pdfLeft && galleryLeft == 0;

  @override
  List<Object?> get props => [picturesLeft, pdfLeft, galleryLeft];
}

/// Deletes what one scan created: its pictures, its PDF and its Gallery
/// copies, each by the URI that was recorded when it was stored (ADR-027).
/// Never by a name or a folder, so a file the scan did not create cannot be
/// touched. A file that fails does not stop the others; the outcome counts
/// what is left per category. Never throws.
class DiscardScan {
  const DiscardScan({
    required this.fileStore,
    required this.gallery,
    required this.logger,
  });

  final ScanFileStore fileStore;
  final GalleryService gallery;
  final AppLogger logger;

  Future<DiscardOutcome> call({
    required StoredScan scan,
    StoredPdf? pdf,
  }) async {
    var pdfLeft = false;
    if (pdf != null) pdfLeft = !await _deleteFile(pdf.uri);

    var picturesLeft = 0;
    var galleryLeft = 0;
    for (final picture in scan.pictures) {
      final uri = picture.uri;
      if (uri == null || !await _deleteFile(uri)) picturesLeft++;
      if (picture.gallery == GalleryCopyStatus.saved) {
        final galleryUri = picture.galleryUri;
        if (galleryUri == null || !await _deleteGallery(galleryUri)) {
          galleryLeft++;
        }
      }
    }
    return DiscardOutcome(
      picturesLeft: picturesLeft,
      pdfLeft: pdfLeft,
      galleryLeft: galleryLeft,
    );
  }

  Future<bool> _deleteFile(String uri) async {
    try {
      await fileStore.deleteByUri(uri);
      return true;
    } catch (error, stackTrace) {
      logger.error(
        'Discard: a file was not deleted',
        error.runtimeType,
        stackTrace,
      );
      return false;
    }
  }

  Future<bool> _deleteGallery(String uri) async {
    try {
      await gallery.deleteImage(uri);
      return true;
    } catch (error, stackTrace) {
      logger.error(
        'Discard: a Gallery copy was not deleted',
        error.runtimeType,
        stackTrace,
      );
      return false;
    }
  }
}
