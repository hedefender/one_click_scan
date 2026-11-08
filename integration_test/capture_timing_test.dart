import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:one_click_scan/domain/lighting/light_metric.dart';
import 'package:one_click_scan/domain/lighting/lighting_config.dart';
import 'package:one_click_scan/services/camera/camera_service.dart';
import 'package:one_click_scan/services/camera/plugin_camera_service.dart';
import 'package:path_provider/path_provider.dart';

/// Phase 6.3, part C: how long is the capture button inactive after a shot?
/// With the REAL camera plugin on the Claude Code emulator (virtual scene).
///
/// The button is inactive while `PluginCameraService.capture` runs. It has
/// three stages (waiting for the light analyser, `takePicture`, moving the
/// file) and this test prints the time of each, for shots taken one after the
/// other while the analyser runs, like a quick Multi Page scan.
/// The emulator is not the phone: its `takePicture` is not the phone's. The
/// number that matters (the analyser wait) does not depend on the camera.
///   tool/run_integration_test.sh `<emulator-id>` integration_test/capture_timing_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  void report(String message) {
    // ignore: avoid_print
    print('CAPTURETIME $message');
  }

  testWidgets('time of the stages of quick shots with the analyser on', (
    tester,
  ) async {
    final cache = await getTemporaryDirectory();
    final pages = Directory('${cache.path}/capture_timing_pages');
    final camera = PluginCameraService(cacheDirectory: pages);
    final opened = await camera.open().timeout(
      const Duration(seconds: 20),
      onTimeout: () => CameraOpenResult.unavailable,
    );
    expect(opened, CameraOpenResult.ready);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: Builder(builder: camera.buildPreview)),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    camera.startLightAnalysis();
    await Future<void>.delayed(const Duration(seconds: 2));

    final totals = <int>[];
    final stops = <int>[];
    final takes = <int>[];
    final paths = <String>[];
    for (var i = 1; i <= 12; i++) {
      // Shots at "random" phases of the analyser's cycle.
      await Future<void>.delayed(Duration(milliseconds: 90 * (i % 5)));
      final watch = Stopwatch()..start();
      final page = await camera.capture(order: i);
      final wall = watch.elapsedMilliseconds;
      paths.add(page.path);
      final t = camera.lastCaptureTimings!;
      totals.add(wall);
      stops.add(t.stopAnalysis.inMilliseconds);
      takes.add(t.takePicture.inMilliseconds);
      report('shot $i: $t, wall $wall ms');
    }
    double mean(List<int> v) => v.reduce((a, b) => a + b) / v.length;
    report(
      'MEAN over ${totals.length}: stopAnalysis ${mean(stops).round()} ms '
      '(max ${stops.reduce((a, b) => a > b ? a : b)}), takePicture '
      '${mean(takes).round()} ms, total ${mean(totals).round()} ms '
      '(max ${totals.reduce((a, b) => a > b ? a : b)})',
    );

    camera.stopLightAnalysis();
    await camera.close();
    for (final path in paths) {
      await File(path).delete();
    }
    if (pages.existsSync()) await pages.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 5)));

  // Phase 6.3, part D: why does the analyser give about 1.5 samples a second
  // when the design says about 2.5? Only a measurement; nothing is changed.
  testWidgets('rate of the analyser samples and what a cycle is made of', (
    tester,
  ) async {
    final cache = await getTemporaryDirectory();
    final camera = PluginCameraService(
      cacheDirectory: Directory('${cache.path}/capture_timing_rate'),
    );
    final opened = await camera.open().timeout(
      const Duration(seconds: 20),
      onTimeout: () => CameraOpenResult.unavailable,
    );
    expect(opened, CameraOpenResult.ready);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: Builder(builder: camera.buildPreview)),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    final stamps = <int>[];
    final watch = Stopwatch();
    final sub = camera.lightSamples.listen((LightMetric _) {
      stamps.add(watch.elapsedMilliseconds);
    });
    camera.startLightAnalysis();
    watch.start();
    await Future<void>.delayed(const Duration(seconds: 15));
    camera.stopLightAnalysis();
    final seconds = watch.elapsedMilliseconds / 1000;
    final gaps = [
      for (var i = 1; i < stamps.length; i++) stamps[i] - stamps[i - 1],
    ];
    final meanGap = gaps.reduce((a, b) => a + b) / gaps.length;
    report(
      'analyser: ${stamps.length} samples in ${seconds.toStringAsFixed(1)} s = '
      '${(stamps.length / seconds).toStringAsFixed(2)} per second; mean gap '
      '${meanGap.round()} ms (min ${gaps.reduce((a, b) => a < b ? a : b)}, max '
      '${gaps.reduce((a, b) => a > b ? a : b)}); sleep between cycles '
      '${LightingConfig.analysisInterval.inMilliseconds} ms, so a cycle itself '
      '(start stream, one frame, stop stream, measure) takes about '
      '${(meanGap - LightingConfig.analysisInterval.inMilliseconds).round()} ms',
    );
    await sub.cancel();
    await camera.close();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
