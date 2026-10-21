import 'package:flutter/widgets.dart';

import '../../core/errors/app_exceptions.dart';
import '../../domain/entities/captured_page.dart';
import 'camera_service.dart';

/// Used on platforms without an implementation, and as the container default.
class UnsupportedCameraService implements CameraService {
  const UnsupportedCameraService();

  @override
  Future<CameraOpenResult> open() async => CameraOpenResult.unavailable;

  @override
  Widget buildPreview(BuildContext context) => const SizedBox.shrink();

  @override
  Future<CapturedPage> capture({required int order}) {
    throw const CameraCaptureException('Camera is not supported');
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> openAppSettings() async {}
}
