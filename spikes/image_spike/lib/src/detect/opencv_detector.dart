import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../geometry/quad.dart';
import 'confidence.dart';
import 'detection.dart';
import 'gray.dart';
import 'polygon.dart';

/// A1: the same page finder as [PureDartDetector], with OpenCV doing the
/// image work: blur, Canny, dilate, findContours, threshold, approxPolyDP.
/// The grey downscale, the Otsu levels and the confidence score are the same
/// Dart code as in A3, so the two detectors differ only in the pixel work.
class OpenCvDetector implements DocumentDetector {
  OpenCvDetector({
    this.maxSide = 640,
    this.maxCandidates = 6,
    this.approxPolyDp = true,
  });

  final int maxSide;
  final int maxCandidates;

  /// true: the four corners come from approxPolyDP (may lie inside the hull);
  /// false: from the enclosing-quad reduction of A3 (never cuts the hull).
  final bool approxPolyDp;

  @override
  String get name =>
      approxPolyDp ? 'A1 OpenCV (approxPolyDP)' : 'A1 OpenCV (enclosing quad)';

  @override
  Detection detect(RgbFrame frame) {
    final sw = Stopwatch()..start();
    final gray = grayDownscaled(frame, maxSide: maxSide);
    final blurredForScore = gaussianBlur5(gray);
    final grad = GradientField.of(blurredForScore, gray.width, gray.height);
    final microsPrepare = sw.elapsedMicroseconds;

    sw
      ..reset()
      ..start();
    final w = gray.width, h = gray.height;
    final src = cv.Mat.fromVec(
      cv.VecU8.fromList(gray.data),
      rows: h,
      cols: w,
      type: cv.MatType.CV_8UC1,
    );
    final blur = cv.gaussianBlur(src, (5, 5), 0);
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
    final polygons = <List<Pt>>[];

    // Edge candidates.
    final hi = grad.percentile(0.92).clamp(20, 120);
    final lo = (hi * 0.4).round();
    // OpenCV's Canny uses the unnormalised Sobel sum, 4 times ours.
    final edges = cv.canny(blur, lo * 4.0, hi * 4.0);
    final closed = cv.dilate(edges, kernel);
    polygons.addAll(_hulls(closed, (w * h * 0.004).round()));
    edges.dispose();
    closed.dispose();

    // Brightness candidates (Otsu levels from the Dart helper).
    final blurBytes = Uint8List.fromList(blur.data);
    final t1 = otsuThreshold(blurBytes);
    final t2 = otsuThreshold(blurBytes, above: t1);
    for (final t in {t1, t2}) {
      final (_, mask) = cv.threshold(blur, t.toDouble(), 255, cv.THRESH_BINARY);
      final dilated = cv.dilate(mask, kernel);
      final opened = cv.erode(dilated, kernel);
      polygons.addAll(_hulls(opened, (w * h * 0.03).round()));
      mask.dispose();
      dilated.dispose();
      opened.dispose();
    }
    src.dispose();
    blur.dispose();
    kernel.dispose();

    final quads = <Quad>[];
    for (final hull in polygons) {
      final q = _quadOf(hull);
      if (q != null) quads.add(q);
    }
    final microsDetect = sw.elapsedMicroseconds;

    sw
      ..reset()
      ..start();
    Quad? best;
    var bestParts = ConfidenceParts.none;
    for (final q in quads) {
      final parts = scoreQuad(q, gray, grad);
      if (best == null || parts.value > bestParts.value) {
        best = q;
        bestParts = parts;
      }
    }
    final microsConfidence = sw.elapsedMicroseconds;
    return Detection(
      quad: best == null
          ? null
          : Quad([
              for (final p in best.p) Pt(p.x * gray.scale, p.y * gray.scale),
            ]),
      confidence: bestParts,
      candidates: quads.length,
      microsPrepare: microsPrepare,
      microsDetect: microsDetect,
      microsConfidence: microsConfidence,
    );
  }

  /// Hulls of the biggest outer contours of a binary picture.
  List<List<Pt>> _hulls(cv.Mat binary, int minArea) {
    final (contours, hierarchy) = cv.findContours(
      binary,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    );
    final found = <(double, List<Pt>)>[];
    for (var i = 0; i < contours.length; i++) {
      final c = contours[i];
      final area = cv.contourArea(c);
      if (area < minArea) continue;
      final pts = [for (final p in c) Pt(p.x.toDouble(), p.y.toDouble())];
      found.add((area, convexHull(pts)));
    }
    contours.dispose();
    hierarchy.dispose();
    found.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final f in found.take(maxCandidates)) f.$2];
  }

  /// approxPolyDP on the hull with growing tolerance until four corners
  /// remain; the enclosing-quad reduction when it cannot (and always keeps
  /// the result that encloses the hull, as A3 does).
  Quad? _quadOf(List<Pt> hull) {
    if (hull.length < 4) return null;
    if (!approxPolyDp) return enclosingQuad(hull);
    final curve = cv.VecPoint.fromList([
      for (final p in hull) cv.Point(p.x.round(), p.y.round()),
    ]);
    final perimeter = cv.arcLength(curve, true);
    Quad? viaCv;
    for (final eps in [0.01, 0.02, 0.03, 0.04, 0.06]) {
      final approx = cv.approxPolyDP(curve, perimeter * eps, true);
      if (approx.length == 4) {
        viaCv = Quad.ordered([
          for (final p in approx) Pt(p.x.toDouble(), p.y.toDouble()),
        ]);
        approx.dispose();
        break;
      }
      approx.dispose();
    }
    curve.dispose();
    return viaCv ?? enclosingQuad(hull);
  }
}
