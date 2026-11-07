import 'package:flutter/widgets.dart';

import '../../domain/entities/captured_page.dart';
import '../../domain/lighting/flash_mode.dart';
import '../../domain/lighting/light_metric.dart';

enum CameraOpenResult {
  ready,

  /// The user denied the camera permission (or it is blocked).
  permissionDenied,

  /// No camera, or it could not be started.
  unavailable,
}

/// Live camera behind an interface, so the plugin type never leaks out of
/// the implementation (and tests use a fake).
abstract interface class CameraService {
  /// Starts the camera. On first use this asks for the camera permission.
  Future<CameraOpenResult> open();

  /// Live preview. Only valid after [open] returned [CameraOpenResult.ready].
  Widget buildPreview(BuildContext context);

  /// Takes a photo into a temporary file in the app cache.
  /// Throws `CameraCaptureException` on failure.
  Future<CapturedPage> capture({required int order});

  /// Releases the camera. Safe to call when it is not open.
  Future<void> close();

  /// Opens the system settings page of this app, so a blocked permission can
  /// be granted.
  Future<void> openAppSettings();

  /// The phone has a flash unit on the back camera. Only valid after [open].
  /// Without one the flash button is not shown.
  bool get hasFlash;

  /// The flash mode applied to the shots (the flash fires on the shot only,
  /// it is never a continuous torch).
  FlashMode get flashMode;

  Future<void> setFlashMode(FlashMode mode);

  /// Tap-to-focus: focus and exposure are measured at [point], given as
  /// fractions (0..1) of the preview. The camera returns to continuous focus
  /// by itself after the time CameraX defines. Never throws.
  Future<void> focusAt(Offset point);

  /// Brightness of the live preview, about 2 to 3 times a second while the
  /// analysis runs (ADR-030). Broadcast; empty when nothing is measured.
  Stream<LightMetric> get lightSamples;

  /// Starts / stops the analysis of the preview. The analysis stops by itself
  /// during a shot and when the camera closes.
  void startLightAnalysis();
  void stopLightAnalysis();
}
