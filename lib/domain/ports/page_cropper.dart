import '../entities/page_crop_outcome.dart';
import '../ocr/ocr_cancellation.dart';

/// Finds the page in a picture and writes it straightened (ADR-029).
///
/// The implementation (`services/imaging/`) runs in a background isolate and
/// never throws: every problem is [PageWholeFrame]. It stops at once when
/// [OcrCancellation] is cancelled or [timeout] passes, and when it does so it
/// has left no file at [target].
abstract interface class PageCropper {
  /// Reads the JPEG at [source], and when a page is found with a confidence of
  /// at least `PageCropConfig.minConfidence` writes the straightened picture as
  /// a JPEG to [target]. [focalLength35mm] is the EXIF 35 mm equivalent focal
  /// length of the original photo (null when it had none).
  Future<PageCropOutcome> crop({
    required String source,
    required String target,
    required int maxSide,
    required int jpegQuality,
    required int? focalLength35mm,
    required Duration timeout,
    OcrCancellation? cancellation,
  });
}
