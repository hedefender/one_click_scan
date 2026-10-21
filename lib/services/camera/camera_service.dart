import 'package:flutter/widgets.dart';

import '../../domain/entities/captured_page.dart';

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
}
