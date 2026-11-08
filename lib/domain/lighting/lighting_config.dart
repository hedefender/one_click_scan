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

  /// Below this paper level the light correction (`flat`) does not help in a
  /// reliable way (phone check of Phase 6.2: a PDF from a shot under about 40
  /// stays unreadable). It is a second, separate threshold: it only changes the
  /// WORDS of the warning (retake first), never whether the warning appears.
  /// Equal to [minPaperLevel] for now, so the second zone is not active until
  /// the dusk calibration (`PHASE_6_2_1_VALIDATION.md`) decides both values.
  static const double enhancementHelpsMinPaperLevel = 40;

  /// The torch (flash On) is switched off by itself after this time without a
  /// shot or a tap-to-focus, and the choice goes back to Auto (ADR-031).
  static const Duration torchIdleTimeout = Duration(seconds: 120);

  /// After the torch changes, the preview samples are ignored for this long:
  /// the camera needs time to settle its exposure, and an old (or half
  /// adjusted) sample would show a false "low light" mark (ADR-031).
  static const Duration torchSettleDelay = Duration(milliseconds: 500);

  /// A paper level that the light correction cannot be expected to repair.
  static bool isTooDarkForEnhancement(
    LightMetric metric, {
    double helpsMin = enhancementHelpsMinPaperLevel,
  }) => metric.paper < helpsMin;

  /// The only place the warning threshold is applied.
  static bool isLowLight(LightMetric metric) => metric.paper < minPaperLevel;
}
