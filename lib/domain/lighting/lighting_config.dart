import 'light_metric.dart';

/// Every constant of the light detection, in ONE place (ADR-030).
///
/// The numbers are in per cent of brightness (0..100) of the Y (luma) level of
/// a reduced picture. [minPaperLevel] starts in the range 30 to 50 decided by
/// the user and is calibrated with the numbers of the diagnostic screen
/// (`PHASE_6_2_VALIDATION.md`).
abstract final class LightingConfig {
  /// A picture whose paper level (95th percentile of Y) is **below** this is
  /// "dark". Raise it to warn more often, lower it to warn less. Starting value
  /// 40 (middle of the 30 to 50 range). Synthetic calibration: a well lit page
  /// is 85 to 100, a shot at about one third of the light is about 30.
  static const double minPaperLevel = 40;

  /// Side (pixels) of the reduced picture the metric is taken from. The
  /// metric needs no detail: the preview analyser and the after-shot check use
  /// the same size order, so their numbers compare.
  static const int thumbnailSide = 160;

  /// Time between two preview samples (about 2.5 per second). The analyser
  /// takes one frame, then sleeps: no frame is copied from the camera between.
  static const Duration analysisInterval = Duration(milliseconds: 400);

  /// Every n-th pixel of the preview's Y plane is read (a coarse grid is
  /// enough for a percentile).
  static const int previewStride = 6;

  /// Contrast (95th minus 5th percentile) under which the diagnostic screen
  /// calls a picture "faint" (thermal paper). It is NOT a reason to warn: more
  /// light does not give faded ink back.
  static const double faintContrast = 20;

  /// The only place the threshold is applied.
  static bool isLowLight(LightMetric metric) => metric.paper < minPaperLevel;
}
