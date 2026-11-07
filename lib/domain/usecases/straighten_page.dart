import '../entities/page_crop_outcome.dart';
import '../entities/upright_image.dart';
import '../imaging/page_crop_config.dart';
import '../ocr/ocr_cancellation.dart';
import '../ocr/ocr_config.dart';
import '../ports/ocr_work_store.dart';
import '../ports/page_cropper.dart';

/// A page after the crop step: the picture the OCR and the PDF will use, and
/// what the crop made of it.
class StraightenedPage {
  const StraightenedPage({required this.image, required this.outcome});

  final UprightImage image;
  final PageCropOutcome outcome;
}

/// Crops the working copy of one page (ADR-029).
///
/// **The PDF never loses content:** whatever goes wrong (low confidence, no
/// page, an exception, a timeout, a cancel) the result is the same working copy
/// as before, the whole frame, and the scan goes on. When the crop is made the
/// new picture replaces the old working copy, whose file is deleted, so a page
/// has exactly one working file. The originals in `./pictures` and the Gallery
/// are never read or touched here.
class StraightenPage {
  const StraightenPage({required this.cropper, required this.workStore});

  final PageCropper cropper;
  final OcrWorkStore workStore;

  /// Never throws.
  Future<StraightenedPage> call(
    UprightImage image, {
    OcrCancellation? cancellation,
  }) async {
    String? target;
    PageCropOutcome outcome;
    try {
      target = await workStore.newImagePath();
      outcome = await cropper.crop(
        source: image.path,
        target: target,
        maxSide: OcrConfig.workingSide,
        jpegQuality: OcrConfig.workingJpegQuality,
        focalLength35mm: image.focalLength35mm,
        timeout: PageCropConfig.timeout,
        cancellation: cancellation,
      );
    } catch (_) {
      outcome = const PageWholeFrame(WholeFrameReason.failed);
    }
    if (outcome is PageCropped && target != null) {
      final straight = UprightImage(
        path: target,
        width: outcome.width,
        height: outcome.height,
        sourceWidth: image.sourceWidth,
        sourceHeight: image.sourceHeight,
        focalLength35mm: image.focalLength35mm,
      );
      await _delete(image.path);
      return StraightenedPage(image: straight, outcome: outcome);
    }
    if (target != null) await _delete(target);
    return StraightenedPage(image: image, outcome: outcome);
  }

  Future<void> _delete(String path) async {
    try {
      await workStore.delete(path);
    } catch (_) {
      // The cache is purged at the next start-up anyway.
    }
  }
}
