import '../entities/scan_flow_mode.dart';
import '../entities/scan_mode.dart';
import 'light_metric.dart';
import 'lighting_config.dart';

/// What to do with a shot, by the light it was taken in (ADR-030).
enum LowLightAction {
  /// Bright enough: nothing to say.
  none,

  /// Single Page in One Click: stop and ask (dialog with three choices).
  askNow,

  /// Multi Page in One Click: a mark and a non-blocking bar on the camera; the
  /// summary comes before the send.
  markPage,

  /// Preview mode: no interruption; the result screen has the banner.
  bannerLater,
}

/// The choices of the dialogs (and of the summary before the send).
enum LowLightChoice { retake, continueAnyway, continueWithEnhancement }

/// The decision logic, pure so it is tested without a screen.
abstract final class LowLightPolicy {
  /// Decision for one shot.
  static LowLightAction onCapture({
    required LightMetric? metric,
    required ScanMode mode,
    required ScanFlowMode flow,
  }) {
    if (metric == null || !LightingConfig.isLowLight(metric)) {
      return LowLightAction.none;
    }
    if (flow == ScanFlowMode.preview) return LowLightAction.bannerLater;
    return mode == ScanMode.single
        ? LowLightAction.askNow
        : LowLightAction.markPage;
  }

  /// A dark page must never be sent silently in One Click: before the scan
  /// goes on (Multi "Done") the summary is shown when a page is flagged and
  /// has no decision yet.
  static bool needsSummary({
    required ScanFlowMode flow,
    required int undecidedDarkPages,
  }) => flow == ScanFlowMode.oneClick && undecidedDarkPages > 0;
}
