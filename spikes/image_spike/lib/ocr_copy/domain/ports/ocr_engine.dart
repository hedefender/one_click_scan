import '../entities/ocr_outcome.dart';
import '../entities/ocr_progress.dart';
import '../entities/upright_image.dart';
import '../ocr/ocr_cancellation.dart';
import '../ocr/ocr_config.dart';

/// Reads the text of an upright image. The implementation (Paddle, in a
/// background isolate) is in `services/ocr/`; nothing outside it knows which
/// engine runs.
abstract interface class OcrEngine {
  /// Loads the models of [packId] ahead of time (for example when the camera
  /// opens), so the first page does not pay for it. Best effort: never throws
  /// and never delays the caller.
  Future<void> preload(String packId);

  /// Reads one page. Always completes with an [OcrOutcome]: errors, a timeout
  /// and a cancel are values, not exceptions.
  Future<OcrOutcome> recognize(
    UprightImage image, {
    required String packId,
    Duration timeout = OcrConfig.pageTimeout,
    OcrCancellation? cancellation,
    void Function(OcrProgress progress)? onProgress,
  });

  /// Closes the model sessions and frees their memory. The engine loads again
  /// on the next [recognize]; [dispose] ends it for good.
  Future<void> release();

  Future<void> dispose();
}
