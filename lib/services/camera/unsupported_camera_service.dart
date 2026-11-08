import 'package:flutter/widgets.dart';

import '../../core/errors/app_exceptions.dart';
import '../../domain/entities/captured_page.dart';
import '../../domain/lighting/flash_mode.dart';
import '../../domain/lighting/light_metric.dart';
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

  @override
  bool get hasFlash => false;

  @override
  FlashMode get flashMode => FlashMode.off;

  @override
  Future<void> setFlashMode(FlashMode mode) async {}

  @override
  bool get torchLit => false;

  @override
  Future<void> setTorchLit(bool lit) async {}

  @override
  Future<void> focusAt(Offset point) async {}

  @override
  Stream<LightMetric> get lightSamples => const Stream<LightMetric>.empty();

  @override
  void startLightAnalysis() {}

  @override
  void stopLightAnalysis() {}
}
