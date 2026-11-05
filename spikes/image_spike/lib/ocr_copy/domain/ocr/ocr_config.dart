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

  /// A full-size decode is never made above this many megapixels, in Dart or
  /// natively. The native path above it does not decode full size: it uses
  /// `inSampleSize`, so the bitmap it creates is at most about 5120 x 5120
  /// (about 105 MB) whatever the size of the file. Kept as the documented
  /// boundary of the policy (Phase 1.6c: a full Dart decode of 200 MP froze
  /// the UI for about 8 s).
  static const fullDecodeMaxMegapixels = 50.0;

  /// Above this many megapixels in the header the image is refused
  /// (`imageTooLarge`) without decoding anything. 400 MP is twice the largest
  /// phone sensor mode seen (200 MP, the Phase 1.6c sample), and a sampled
  /// decode of it is a long side of 20000 px scaled by 1/4. The memory of the
  /// sampled decode does not grow with the file; the time does (reading the
  /// JPEG), which the 45 s page timeout bounds.
  static const maxMegapixels = 400.0;

  // ------------------------------------------------------------------ policy

  /// Longest time one page may take, from the moment its recognition starts.
  static const pageTimeout = Duration(seconds: 45);

  /// Lines whose confidence (mean of the per-character probabilities) is
  /// below this are flagged as filtered. They are kept in the result; only the
  /// visible text leaves them out. 0.65 is the user's decision after the first
  /// phone check. Observed: pen strokes that are not text scored 0.38 to 0.60
  /// (emulator and phone), clean, blurred and faint printed text 0.96 to 1.00
  /// on invented pages. PaddleOCR's own `drop_score` default is 0.5.
  static const minLineConfidence = 0.65;

  /// Lines from here up to [minLineConfidence] are "borderline": kept, but
  /// counted on the check screen so the effect of the threshold on real
  /// documents is visible (numbers only).
  static const borderlineConfidence = 0.5;

  /// How long a model-preload request may take before the camera screen
  /// stops caring. The preload never blocks the camera.
  static const preloadTimeout = Duration(seconds: 30);
}
