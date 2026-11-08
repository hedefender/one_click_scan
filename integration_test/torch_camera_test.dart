import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:one_click_scan/domain/lighting/flash_mode.dart';
import 'package:one_click_scan/domain/lighting/light_metric.dart';
import 'package:one_click_scan/services/camera/camera_service.dart';
import 'package:one_click_scan/services/camera/plugin_camera_service.dart';
import 'package:path_provider/path_provider.dart';

/// Phase 6.2.1 (ADR-031) with the REAL camera plugin on the Claude Code
/// emulator (virtual scene, never the webcam).
///
/// What this CAN show: the torch switch does not break the camera, the
/// analyser (its duty cycle starts and stops the image stream) or the shot;
/// without a flash unit no torch call is made at all; closing leaves the
/// torch flag out.
///
/// What this CANNOT show, and says so in the log (it goes to
/// `PHASE_6_2_1_VALIDATION.md` for the phone): that the LED really lights, that
/// it survives the analyser's start/stop of the image stream, that a shot with
/// the torch lit has no second flash, and that the exposure settles. The
/// `torchLit` flag is what the app believes; the plugin does not report the
/// real state of the LED.
///   tool/run_integration_test.sh `<emulator-id>` integration_test/torch_camera_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  void report(String message) {
    // ignore: avoid_print
    print('TORCHCAM $message');
  }

  testWidgets('the torch switch does not break camera, analyser or shot', (
    tester,
  ) async {
    final cache = await getTemporaryDirectory();
    final pages = Directory('${cache.path}/torch_cam_pages');
    final camera = PluginCameraService(cacheDirectory: pages);
    final opened = await camera.open().timeout(
      const Duration(seconds: 20),
      onTimeout: () => CameraOpenResult.unavailable,
    );
    expect(
      opened,
      CameraOpenResult.ready,
      reason: 'grant CAMERA with adb (tool/run_integration_test.sh does)',
    );
    report('hasFlash on this emulator: ${camera.hasFlash}');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: Builder(builder: camera.buildPreview)),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    final samples = <LightMetric>[];
    final sub = camera.lightSamples.listen(samples.add);
    camera.startLightAnalysis();

    // On is only a mode: it never lights the torch by itself.
    await camera.setFlashMode(FlashMode.on);
    expect(camera.torchLit, isFalse);
    report('mode On set, torchLit=${camera.torchLit} (expected false)');

    await camera.setTorchLit(true);
    if (camera.hasFlash) {
      expect(camera.torchLit, isTrue);
      report('torch lit by the plugin call (the LED is NOT verified here)');
    } else {
      expect(
        camera.torchLit,
        isFalse,
        reason: 'no flash unit: no torch call must be made',
      );
      report('no flash unit: setTorchLit(true) made no torch call, as built');
    }

    // The analyser keeps delivering while the torch is "lit".
    final before = samples.length;
    await tester.pump(const Duration(seconds: 4));
    await Future<void>.delayed(const Duration(seconds: 4));
    expect(samples.length, greaterThan(before), reason: 'analyser stalled');
    report('samples with the torch switch on: ${samples.length - before}');

    // A shot with the torch lit; the analysis goes on after it.
    final page = await camera.capture(order: 1);
    expect(File(page.path).existsSync(), isTrue);
    final afterShot = samples.length;
    await tester.pump(const Duration(seconds: 3));
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(samples.length, greaterThan(afterShot));
    expect(camera.torchLit, camera.hasFlash, reason: 'a shot kept the torch');
    report('shot + analyser after it: ok, torchLit=${camera.torchLit}');

    await camera.focusAt(const Offset(0.5, 0.5));
    report('tap-to-focus with the torch switch on: no error');

    // Auto and Off put the torch out; on a phone this also ends the light.
    await camera.setFlashMode(FlashMode.auto);
    expect(camera.torchLit, isFalse);
    await camera.setFlashMode(FlashMode.on);
    await camera.setTorchLit(true);
    await camera.setTorchLit(false);
    expect(camera.torchLit, isFalse);
    await camera.setTorchLit(true);
    await camera.close();
    expect(camera.torchLit, isFalse, reason: 'close puts the torch out');
    report('Auto / Off / close: torchLit=false');

    camera.stopLightAnalysis();
    await sub.cancel();
    await File(page.path).delete();
    if (pages.existsSync()) await pages.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
