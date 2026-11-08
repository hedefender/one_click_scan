import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart' hide FlashMode;
import 'package:camera/camera.dart' as plugin show FlashMode;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/errors/app_exceptions.dart';
import '../../domain/entities/captured_page.dart';
import '../../domain/lighting/flash_mode.dart';
import '../../domain/lighting/light_metric.dart';
import '../../domain/lighting/lighting_config.dart';
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
  bool _hasFlash = false;
  FlashMode _flashMode = FlashMode.off;
  bool _torchLit = false;

  final _samples = StreamController<LightMetric>.broadcast();
  bool _analysing = false;
  Future<void>? _loop;
  int _loopGeneration = 0;

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
      await controller.setFlashMode(plugin.FlashMode.off);
      _flashMode = FlashMode.off;
      _torchLit = false;
      _hasFlash = await _askHasFlash();
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
    // The analysis stops during the shot and starts again after it.
    final wasAnalysing = _analysing;
    await _stopAnalysis();
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
    } finally {
      if (wasAnalysing && _controller == controller) startLightAnalysis();
    }
  }

  @override
  Future<void> close() async {
    await _stopAnalysis();
    final controller = _controller;
    _controller = null;
    final wasLit = _torchLit;
    _torchLit = false;
    // Disposing unbinds the camera, which also puts the torch out; when it is
    // lit it is put out first on purpose, so it does not depend on that side
    // effect. Not done otherwise: it would only add a rebuild of the preview
    // between the release and the dispose.
    if (wasLit && controller != null && controller.value.isInitialized) {
      try {
        await controller.setFlashMode(plugin.FlashMode.off);
      } on CameraException {
        // dispose below still releases the camera and with it the torch.
      }
    }
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

  Future<bool> _askHasFlash() async {
    try {
      return await _systemChannel.invokeMethod<bool>('hasFlashUnit') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  bool get hasFlash => _hasFlash;

  @override
  FlashMode get flashMode => _flashMode;

  @override
  Future<void> setFlashMode(FlashMode mode) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || !_hasFlash) {
      return;
    }
    try {
      // On is the torch: the shot has no flash of its own, so the capture mode
      // is Off (the plugin does the same when the torch is lit). The torch is
      // lit only by setTorchLit.
      await controller.setFlashMode(switch (mode) {
        FlashMode.off || FlashMode.on => plugin.FlashMode.off,
        FlashMode.auto => plugin.FlashMode.auto,
      });
      _torchLit = false;
      _flashMode = mode;
    } on CameraException {
      // The mode stays as it was; the button shows the real one.
    }
  }

  @override
  bool get torchLit => _torchLit;

  @override
  Future<void> setTorchLit(bool lit) async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        !_hasFlash ||
        _flashMode != FlashMode.on ||
        lit == _torchLit) {
      return;
    }
    try {
      await controller.setFlashMode(
        lit ? plugin.FlashMode.torch : plugin.FlashMode.off,
      );
      _torchLit = lit;
    } on CameraException {
      // The torch stays as it was; the button shows the real state.
    }
  }

  @override
  Future<void> focusAt(Offset point) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final clamped = Offset(point.dx.clamp(0.0, 1.0), point.dy.clamp(0.0, 1.0));
    try {
      // CameraX starts one FocusMeteringAction per call; the plugin combines
      // the two points, and CameraX returns to continuous focus by itself.
      await controller.setFocusPoint(clamped);
      await controller.setExposurePoint(clamped);
    } on CameraException {
      // Focus is a convenience; a failure changes nothing.
    }
  }

  @override
  Stream<LightMetric> get lightSamples => _samples.stream;

  @override
  void startLightAnalysis() {
    final controller = _controller;
    if (_analysing || controller == null) return;
    _analysing = true;
    final generation = ++_loopGeneration;
    _loop = _analysisLoop(controller, generation);
  }

  @override
  void stopLightAnalysis() => unawaited(_stopAnalysis());

  Future<void> _stopAnalysis() async {
    _analysing = false;
    _loopGeneration++;
    final loop = _loop;
    _loop = null;
    if (loop != null) await loop;
  }

  /// Duty cycle: the analyser is switched on only to receive ONE frame, then
  /// off for [LightingConfig.analysisInterval]. The plugin copies every frame
  /// it has an analyser for into Dart (about 30 per second, 460 KB each), so
  /// this is what keeps the cost of a low rate real. The metric is computed in
  /// a background isolate, never in the UI isolate.
  Future<void> _analysisLoop(
    CameraController controller,
    int generation,
  ) async {
    bool alive() =>
        _analysing &&
        generation == _loopGeneration &&
        _controller == controller;
    while (alive()) {
      final frame = Completer<CameraImage>();
      try {
        await controller.startImageStream((image) {
          if (!frame.isCompleted) frame.complete(image);
        });
      } on CameraException {
        break;
      }
      CameraImage? image;
      try {
        image = await frame.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        image = null;
      }
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } on CameraException {
        break;
      }
      if (image != null && alive()) {
        final metric = await _measure(image);
        if (metric != null && alive() && !_samples.isClosed) {
          _samples.add(metric);
        }
      }
      await Future<void>.delayed(LightingConfig.analysisInterval);
    }
  }

  Future<LightMetric?> _measure(CameraImage image) async {
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    final job = _LumaJob(
      TransferableTypedData.fromList([plane.bytes]),
      image.width,
      image.height,
      plane.bytesPerRow,
    );
    try {
      return await Isolate.run(() => _measureLuma(job));
    } catch (_) {
      return null;
    }
  }
}

class _LumaJob {
  const _LumaJob(this.bytes, this.width, this.height, this.rowStride);

  final TransferableTypedData bytes;
  final int width;
  final int height;
  final int rowStride;
}

LightMetric? _measureLuma(_LumaJob job) => LightMetric.fromLuma(
  job.bytes.materialize().asUint8List(),
  width: job.width,
  height: job.height,
  rowStride: job.rowStride,
  stride: LightingConfig.previewStride,
);
