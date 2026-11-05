import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../src/detect/detection.dart';
import '../src/detect/opencv_detector.dart';
import '../src/detect/pure_dart_detector.dart';
import '../src/geometry/quad.dart';
import '../src/image/enhance.dart';
import '../src/image/opencv_rectify.dart';
import '../src/image/rectify.dart';

/// Which detector and warp the phone screens use.
enum Engine {
  dart('A3 (Dart)'),
  dartSmall('A3 μικρά (Dart)'),
  openCv('A1 (OpenCV)');

  const Engine(this.label);
  final String label;
}

/// The crop is used when the detection reaches this confidence (section 4.3 of
/// docs/IMAGE_SPIKE_RESULTS.md).
const trustThreshold = 0.5;

/// Longest side of the working frame (the evaluation used 1536 x 2048).
const frameLongSide = 2048;

DocumentDetector detectorFor(Engine e) => switch (e) {
  Engine.dart => PureDartDetector(),
  Engine.dartSmall => PureDartDetector(
    areaLow: 0.01,
    areaHigh: 0.04,
    minBrightFraction: 0.008,
    label: 'A3 small-area',
  ),
  Engine.openCv => OpenCvDetector(approxPolyDp: false),
};

RgbFrame warpFor(Engine e, RgbFrame f, Quad q, double focalPx) => switch (e) {
  Engine.dart || Engine.dartSmall => warpToQuadDart(f, q, focalPx: focalPx),
  Engine.openCv => warpToQuadOpenCv(f, q, focalPx: focalPx),
};

Uint8List _jpg(RgbFrame f, int quality) => img.encodeJpg(
  img.Image.fromBytes(
    width: f.width,
    height: f.height,
    bytes: f.rgb.buffer,
    numChannels: 3,
  ),
  quality: quality,
);

/// What one photo became. Only pictures and numbers, never any text of the
/// page.
class PhotoResult {
  const PhotoResult({
    required this.frameJpg,
    required this.afterJpg,
    required this.afterFlatJpg,
    required this.used,
    required this.score,
    required this.otherScore,
    required this.frameWidth,
    required this.frameHeight,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.focalPx,
    required this.decodeMs,
    required this.detectMs,
    required this.warpMs,
    required this.flatMs,
  });

  /// The whole frame (what the app has today).
  final Uint8List frameJpg;

  /// The crop when [used], else the whole frame again.
  final Uint8List afterJpg;

  /// [afterJpg] with the shadow removed.
  final Uint8List afterFlatJpg;
  final bool used;
  final double score;

  /// Confidence of the other engine on the same frame (for comparison).
  final double otherScore;
  final int frameWidth;
  final int frameHeight;
  final int sourceWidth;
  final int sourceHeight;

  /// 0 when the photo has no 35 mm focal length.
  final double focalPx;
  final int decodeMs;
  final int detectMs;
  final int warpMs;
  final int flatMs;
}

/// Reads a photo file, rotates it upright by its EXIF, scales it to
/// [frameLongSide], finds the page, straightens it and makes the shadow-free
/// variant. Runs in an isolate.
Future<PhotoResult> processPhoto(String path, Engine engine) =>
    Isolate.run(() => processPhotoSync(path, engine));

PhotoResult processPhotoSync(String path, Engine engine) {
  final sw = Stopwatch()..start();
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) throw StateError('unreadable photo');
  final sourceWidth = decoded.width, sourceHeight = decoded.height;
  final f35 = decoded.exif.exifIfd.data[0xA405]?.toInt() ?? 0;
  var image = img.bakeOrientation(decoded);
  final longest = math.max(image.width, image.height);
  if (longest > frameLongSide) {
    final s = frameLongSide / longest;
    image = img.copyResize(
      image,
      width: (image.width * s).round(),
      height: (image.height * s).round(),
      interpolation: img.Interpolation.average,
    );
  }
  final rgb = image.convert(numChannels: 3);
  final frame = RgbFrame(
    rgb.width,
    rgb.height,
    rgb.getBytes(order: img.ChannelOrder.rgb),
  );
  final decodeMs = sw.elapsedMilliseconds;
  // 35 mm equivalent focal length -> pixels (diagonal of 43.27 mm).
  final focalPx = f35 > 0
      ? f35 *
            math.sqrt(frame.width * frame.width + frame.height * frame.height) /
            43.27
      : 0.0;
  return _finish(frame, engine, focalPx, sourceWidth, sourceHeight, decodeMs);
}

/// Same as [processPhotoSync] for a frame already in memory (the synthetic
/// pictures of the background test).
PhotoResult processFrame(RgbFrame frame, Engine engine, double focalPx) =>
    _finish(frame, engine, focalPx, frame.width, frame.height, 0);

PhotoResult _finish(
  RgbFrame frame,
  Engine engine,
  double focalPx,
  int sourceWidth,
  int sourceHeight,
  int decodeMs,
) {
  var sw = Stopwatch()..start();
  final det = detectorFor(engine).detect(frame);
  final detectMs = sw.elapsedMilliseconds;
  final other = detectorFor(
    engine == Engine.openCv ? Engine.dart : Engine.openCv,
  ).detect(frame);
  final quad = det.quad;
  final used = quad != null && det.score >= trustThreshold;
  sw = Stopwatch()..start();
  final after = used ? warpFor(engine, frame, quad, focalPx) : frame;
  final warpMs = sw.elapsedMilliseconds;
  sw = Stopwatch()..start();
  final flat = flattenLight(after);
  final flatMs = sw.elapsedMilliseconds;
  return PhotoResult(
    frameJpg: _jpg(frame, 90),
    afterJpg: used ? _jpg(after, 90) : _jpg(frame, 90),
    afterFlatJpg: _jpg(flat, 90),
    used: used,
    score: det.score,
    otherScore: other.score,
    frameWidth: frame.width,
    frameHeight: frame.height,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    focalPx: focalPx,
    decodeMs: decodeMs,
    detectMs: detectMs,
    warpMs: warpMs,
    flatMs: flatMs,
  );
}
