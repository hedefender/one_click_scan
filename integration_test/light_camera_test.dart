import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:one_click_scan/domain/lighting/light_metric.dart';
import 'package:one_click_scan/services/camera/camera_service.dart';
import 'package:one_click_scan/services/camera/plugin_camera_service.dart';
import 'package:path_provider/path_provider.dart';

/// Phase 6.2 with the REAL camera plugin on the Claude Code emulator (its back
/// camera is the virtual scene, never the webcam): the cost of the preview
/// analyser on the frames of the screen, the sample rate, a shot taken while
/// the analysis runs, and tap-to-focus that must not throw.
///
/// What an emulator cannot say (written in `PHASE_6_2_VALIDATION.md`): the real
/// flash, the real light of a room, the focus of a real lens, and the cost on
/// the phone. Frames over 33 ms are counted like in the spike of Phase 6.0.
///   tool/run_integration_test.sh `<emulator-id>` integration_test/light_camera_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  void report(String message) {
    // ignore: avoid_print
    print('LIGHTCAM $message');
  }

  Future<Directory> pagesDir() async {
    final cache = await getTemporaryDirectory();
    return Directory('${cache.path}/light_cam_pages');
  }

  /// Frame times (build + raster, ms) of [seconds] seconds of the live preview.
  Future<List<double>> measureFrames(
    WidgetTester tester,
    Duration duration,
  ) async {
    final spans = <double>[];
    void onTimings(List<FrameTiming> timings) {
      for (final t in timings) {
        spans.add(t.totalSpan.inMicroseconds / 1000);
      }
    }

    SchedulerBinding.instance.addTimingsCallback(onTimings);
    await tester.pump(duration);
    await Future<void>.delayed(duration);
    await tester.pump(const Duration(milliseconds: 200));
    SchedulerBinding.instance.removeTimingsCallback(onTimings);
    return spans;
  }

  String stats(List<double> spans) {
    if (spans.isEmpty) return 'no frames';
    final sorted = [...spans]..sort();
    final over33 = spans.where((s) => s > 33).length;
    final p95 =
        sorted[(sorted.length * 0.95).floor().clamp(0, sorted.length - 1)];
    return '${spans.length} frames, mean '
        '${(spans.reduce((a, b) => a + b) / spans.length).toStringAsFixed(1)} '
        'ms, p95 ${p95.toStringAsFixed(1)} ms, max '
        '${sorted.last.toStringAsFixed(1)} ms, over 33 ms: $over33';
  }

  testWidgets('analyser: cost on the preview, sample rate, shot and focus', (
    tester,
  ) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final pages = await pagesDir();
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

    // 1. Preview alone.
    final off = await measureFrames(tester, const Duration(seconds: 8));
    report('analysis OFF: ${stats(off)}');

    // 2. Preview with the analyser on (2.5 samples per second by design).
    final samples = <LightMetric>[];
    final sub = camera.lightSamples.listen(samples.add);
    camera.startLightAnalysis();
    final started = DateTime.now();
    final on = await measureFrames(tester, const Duration(seconds: 8));
    final elapsed = DateTime.now().difference(started).inMilliseconds / 1000;
    report('analysis ON:  ${stats(on)}');
    report(
      'samples: ${samples.length} in ${elapsed.toStringAsFixed(1)} s '
      '(${(samples.length / elapsed).toStringAsFixed(2)} per second)',
    );
    expect(samples, isNotEmpty, reason: 'the analyser delivered no sample');
    final last = samples.last;
    report(
      'virtual scene metric: paper ${last.paper.toStringAsFixed(1)}, '
      'contrast ${last.contrast.toStringAsFixed(1)}',
    );

    // 3. A shot while the analysis runs; the analysis goes on after it.
    final before = samples.length;
    final page = await camera.capture(order: 1);
    expect(File(page.path).existsSync(), isTrue);
    await tester.pump(const Duration(seconds: 3));
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(
      samples.length,
      greaterThan(before),
      reason: 'the analysis did not start again after the shot',
    );
    report('shot while analysing: ok, samples went on after it');

    // 4. Tap-to-focus and the flash mode must never throw on any phone.
    await camera.focusAt(const Offset(0.5, 0.5));
    await camera.focusAt(const Offset(0.1, 0.9));
    report('focusAt: no error');

    camera.stopLightAnalysis();
    await sub.cancel();
    await camera.close();
    await File(page.path).delete();
    if (pages.existsSync()) await pages.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 6)));
}
