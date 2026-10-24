import '../../domain/entities/ocr_outcome.dart';
import '../../domain/entities/ocr_progress.dart';
import '../../domain/entities/upright_image.dart';
import '../../domain/ocr/ocr_cancellation.dart';
import '../../domain/ocr/ocr_config.dart';
import '../../domain/ports/ocr_engine.dart';

/// Engine for platforms without OCR (and the default of the container, so
/// tests never load a model by accident).
class UnsupportedOcrEngine implements OcrEngine {
  const UnsupportedOcrEngine();

  @override
  Future<void> preload(String packId) async {}

  @override
  Future<OcrOutcome> recognize(
    UprightImage image, {
    required String packId,
    Duration timeout = OcrConfig.pageTimeout,
    OcrCancellation? cancellation,
    void Function(OcrProgress progress)? onProgress,
  }) async => const OcrFailed(OcrFailureReason.unsupported);

  @override
  Future<void> release() async {}

  @override
  Future<void> dispose() async {}
}
