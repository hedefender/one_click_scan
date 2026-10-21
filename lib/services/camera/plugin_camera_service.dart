import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/errors/app_exceptions.dart';
import '../../domain/entities/captured_page.dart';
import 'camera_service.dart';

/// `camera` plugin implementation (on Android the endorsed CameraX backend).
/// The plugin's types stay inside this file.
class PluginCameraService implements CameraService {
  PluginCameraService({
    required this.cacheDirectory,
    MethodChannel? systemChannel,
  }) : _systemChannel = systemChannel ?? const MethodChannel(systemChannelName);

  /// Must match `CHANNEL` in SystemHandler.kt.
  static const systemChannelName = 'com.example.one_click_scan/system';

  /// Where captured pages are moved right after the shot.
  final Directory cacheDirectory;
  final MethodChannel _systemChannel;

  CameraController? _controller;
  int _shots = 0;

  @override
  Future<CameraOpenResult> open() async {
    await close();
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return CameraOpenResult.unavailable;
      final description = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        description,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);
      _controller = controller;
      return CameraOpenResult.ready;
    } on CameraException catch (error) {
      if (error.code.startsWith('CameraAccess')) {
        return CameraOpenResult.permissionDenied;
      }
      return CameraOpenResult.unavailable;
    }
  }

  @override
  Widget buildPreview(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return CameraPreview(controller);
  }

  @override
  Future<CapturedPage> capture({required int order}) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw const CameraCaptureException('Camera is not open');
    }
    try {
      final shot = await controller.takePicture();
      await cacheDirectory.create(recursive: true);
      _shots++;
      final target = File(
        '${cacheDirectory.path}${Platform.pathSeparator}'
        'page_${DateTime.now().microsecondsSinceEpoch}_$_shots.jpg',
      );
      await File(shot.path).copy(target.path);
      try {
        await File(shot.path).delete();
      } on FileSystemException {
        // The plugin's own cache file; the system clears it eventually.
      }
      return CapturedPage(path: target.path, order: order);
    } on CameraException catch (error) {
      throw CameraCaptureException(error.code);
    } on FileSystemException catch (error) {
      throw CameraCaptureException(error.message);
    }
  }

  @override
  Future<void> close() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }

  @override
  Future<void> openAppSettings() async {
    try {
      await _systemChannel.invokeMethod<void>('openAppSettings');
    } on PlatformException {
      // Nothing more to do; the message on screen still explains the problem.
    }
  }
}
