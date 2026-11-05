import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'dart:ui' show FrameTiming;

import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

import '../src/detect/detection.dart';
import '../src/geometry/quad.dart';
import 'ocr_service.dart';
import 'pipeline.dart';

/// What one run of the background test measured (numbers only).
class BackgroundReport {
  BackgroundReport({
    required this.pages,
    required this.straighten,
    required this.intervalMs,
    required this.engine,
    required this.withOcr,
  });

  final int pages;

  /// The crop step is on ("new"); off is what the app does today.
  final bool straighten;
  final int intervalMs;
  final Engine engine;
  final bool withOcr;

  /// Milliseconds from the start to the moment of the last shot.
  int lastShotMs = 0;

  /// Milliseconds from the last shot to the end of all the work: what the user
  /// waits for after "Done".
  int waitAfterLastMs = 0;
  int totalMs = 0;
  int croppedPages = 0;
  final prepareMs = <int>[];
  final ocrMs = <int>[];
  int frames = 0;
  int slowFrames = 0;
  int verySlowFrames = 0;
  int worstFrameMs = 0;
  int peakRssMb = 0;

  String summary() =>
      'pages $pages ${straighten ? 'crop+OCR' : 'today (OCR only)'} '
      'interval ${intervalMs}ms ${engine.name} ocr=$withOcr | '
      'last shot at ${lastShotMs}ms, wait after last shot ${waitAfterLastMs}ms, '
      'total ${totalMs}ms | cropped $croppedPages | '
      'prepare median ${_median(prepareMs)}ms, ocr median ${_median(ocrMs)}ms | '
      'frames $frames, over 16ms $slowFrames, over 33ms $verySlowFrames, '
      'worst ${worstFrameMs}ms | peak RSS ${peakRssMb}MB';
}

int _median(List<int> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
  return s[s.length ~/ 2];
}

/// What the worker isolate returns for one page.
class _Prepared {
  const _Prepared(this.jpg, this.width, this.height, this.cropped, this.ms);

  final TransferableTypedData jpg;
  final int width;
  final int height;
  final bool cropped;
  final int ms;
}

/// The preparation of a page in an isolate. Both modes decode and re-encode
/// the picture (the app does that too: its working copy); only `straighten`
/// adds the detection and the warp.
Future<_Prepared> _prepare(Uint8List jpeg, bool straighten, Engine engine) {
  return Isolate.run(() {
    final sw = Stopwatch()..start();
    final decoded = img.decodeJpg(jpeg)!;
    final rgb = decoded.convert(numChannels: 3);
    var frame = RgbFrame(
      rgb.width,
      rgb.height,
      rgb.getBytes(order: img.ChannelOrder.rgb),
    );
    var cropped = false;
    if (straighten) {
      final det = detectorFor(engine).detect(frame);
      final Quad? q = det.quad;
      if (q != null && det.score >= trustThreshold) {
        frame = warpFor(engine, frame, q, 0);
        cropped = true;
      }
    }
    final out = img.encodeJpg(
      img.Image.fromBytes(
        width: frame.width,
        height: frame.height,
        bytes: frame.rgb.buffer,
        numChannels: 3,
      ),
      quality: 95,
    );
    return _Prepared(
      TransferableTypedData.fromList([out]),
      frame.width,
      frame.height,
      cropped,
      sw.elapsedMilliseconds,
    );
  });
}

/// Simulates the shots of a Multi Page scan: one page every [intervalMs]
/// (0 = all at once), each one prepared in an isolate and read by the OCR one
/// after the other, as `OcrSession` of the app does. `onProgress` reports how
/// many pages are finished.
Future<BackgroundReport> runBackgroundTest({
  required List<Uint8List> jpegs,
  required bool straighten,
  required int intervalMs,
  required Engine engine,
  required SpikeOcr? ocr,
  void Function(int done, int total)? onProgress,
  String pack = 'greek',
}) async {
  final report = BackgroundReport(
    pages: jpegs.length,
    straighten: straighten,
    intervalMs: intervalMs,
    engine: engine,
    withOcr: ocr != null,
  );
  final timings = _FrameWatch(report);
  timings.start();
  final total = Stopwatch()..start();
  final queue = <Uint8List>[];
  var shotsDone = false;
  var done = 0;
  final wake = StreamController<void>.broadcast();

  final worker = () async {
    var next = 0;
    while (true) {
      if (next >= queue.length) {
        if (shotsDone) break;
        await wake.stream.first;
        continue;
      }
      final jpeg = queue[next++];
      final p = await _prepare(jpeg, straighten, engine);
      report.prepareMs.add(p.ms);
      if (p.cropped) report.croppedPages++;
      if (ocr != null) {
        final bytes = p.jpg.materialize().asUint8List();
        final file = ocr.writeTemp(bytes);
        try {
          final n = await ocr.readFile(
            file,
            width: p.width,
            height: p.height,
            pack: pack,
          );
          report.ocrMs.add(n.ms);
        } finally {
          file.deleteSync();
        }
      }
      done++;
      onProgress?.call(done, jpegs.length);
    }
  }();

  for (var i = 0; i < jpegs.length; i++) {
    if (i > 0 && intervalMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: intervalMs));
    }
    queue.add(jpegs[i]);
    wake.add(null);
  }
  report.lastShotMs = total.elapsedMilliseconds;
  shotsDone = true;
  wake.add(null);
  await worker;
  report.totalMs = total.elapsedMilliseconds;
  report.waitAfterLastMs = report.totalMs - report.lastShotMs;
  report.peakRssMb = (ProcessInfo.maxRss / 1e6).round();
  timings.stop();
  await wake.close();
  return report;
}

/// Counts the frames of the app's own UI that took too long while the test ran
/// (a sign that the background work would make a live preview stutter).
class _FrameWatch {
  _FrameWatch(this.report);

  final BackgroundReport report;

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final ms = t.totalSpan.inMilliseconds;
      report.frames++;
      if (ms > 16) report.slowFrames++;
      if (ms > 33) report.verySlowFrames++;
      if (ms > report.worstFrameMs) report.worstFrameMs = ms;
    }
  }

  void start() => WidgetsBinding.instance.addTimingsCallback(_onTimings);

  void stop() => WidgetsBinding.instance.removeTimingsCallback(_onTimings);
}
