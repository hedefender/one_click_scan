/// Every tunable of the OCR pipeline in one place (no magic numbers in the
/// code that uses them). The values come from the phone measurements of
/// `docs/OCR_SPIKE_RESULTS.md` sections 9 to 11; the reason for each is in
/// `docs/DECISIONS.md` (ADR-010 to ADR-014).
abstract final class OcrConfig {
  // ----------------------------------------------------------- engine tuning

  /// Longest side of the detection input (rounded to a multiple of 32). The
  /// phone peak memory was about 616 MB at 960 and 1031 MB at 1280.
  static const detectionSide = 960;

  /// ONNX Runtime intra-op threads (the spike default; the thread grid on the
  /// phone is still open).
  static const threads = 4;

  /// Recognition crops per `run` call. Batch 1: a batch is as wide as its
  /// widest line, and batch 4 or 8 was 40% to 70% slower on the phone.
  static const recognitionBatch = 1;

  // --------------------------------------------------------------- the image

  /// Longest side of the upright working copy.
  static const workingSide = 2560;

  /// JPEG quality of the working copy (it is also the picture of the later
  /// PDF phase, so it is written once with a high quality).
  static const workingJpegQuality = 95;

  /// Images up to this many megapixels are decoded with `package:image` in a
  /// background isolate; larger ones are decoded natively, down-scaled while
  /// decoding.
  static const dartDecodeMaxMegapixels = 8.0;

  /// Above this many megapixels the image is refused: the header is read
  /// first and nothing is decoded. A Dart decode of 200 MP took about 8 s of
  /// frozen UI on the phone (the ANR of Phase 1.6c).
  static const maxMegapixels = 50.0;

  // ------------------------------------------------------------------ policy

  /// Longest time one page may take, from the moment its recognition starts.
  static const pageTimeout = Duration(seconds: 45);

  /// Lines whose confidence (mean of the per-character probabilities) is
  /// below this are flagged as filtered. They are kept in the result; only the
  /// visible text leaves them out. 0.5 is the `drop_score` default of
  /// PaddleOCR itself; the spike recorded only mean confidences, so there is
  /// no tuned figure of our own (see `docs/PHASE_2_VALIDATION.md`).
  static const minLineConfidence = 0.5;

  /// How long a model-preload request may take before the camera screen
  /// stops caring. The preload never blocks the camera.
  static const preloadTimeout = Duration(seconds: 30);
}
