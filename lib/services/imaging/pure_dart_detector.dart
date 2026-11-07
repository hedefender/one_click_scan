import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/imaging/quad.dart';
import '../../domain/imaging/page_crop_config.dart';
import 'confidence.dart';
import 'detection.dart';
import 'gray.dart';
import 'polygon.dart';

/// A3: the classic page finder written in plain Dart on typed lists (ADR-029).
///
/// Two sources of candidate outlines, both reduced to an enclosing quad (it
/// always contains the hull, so it cannot cut the page) and scored:
///  * edges: blur, Sobel, thin (non-maximum suppression), hysteresis,
///    close small gaps, connected pieces, hull of each big piece;
///  * brightness: Otsu on the grey picture (paper is the bright class), and
///    Otsu again inside the bright class, connected pieces, hull.
class PureDartDetector {
  const PureDartDetector({
    this.maxSide = PageCropConfig.detectionSide,
    this.maxCandidates = PageCropConfig.maxCandidates,
    this.areaLow = PageCropConfig.areaLow,
    this.areaHigh = PageCropConfig.areaHigh,
    this.minBrightFraction = PageCropConfig.minBrightFraction,
  });

  /// Share of the frame at which the area part of the confidence starts to
  /// rise and where it reaches 1.
  final double areaLow;
  final double areaHigh;

  /// Smallest bright piece (share of the frame) kept as a candidate.
  final double minBrightFraction;

  final int maxSide;
  final int maxCandidates;

  Detection detect(RgbFrame frame) {
    final gray = grayDownscaled(frame, maxSide: maxSide);
    final blurred = gaussianBlur5(gray);
    final grad = GradientField.of(blurred, gray.width, gray.height);

    final polygons = <List<Pt>>[];
    polygons.addAll(_edgeCandidates(blurred, gray.width, gray.height, grad));
    polygons.addAll(_brightnessCandidates(blurred, gray.width, gray.height));
    final quads = <Quad>[];
    for (final hull in polygons) {
      final q = enclosingQuad(hull);
      if (q != null) quads.add(q);
    }

    Quad? best;
    var bestParts = ConfidenceParts.none;
    for (final q in quads) {
      final parts = scoreQuad(
        q,
        gray,
        grad,
        areaLow: areaLow,
        areaHigh: areaHigh,
      );
      if (best == null || parts.value > bestParts.value) {
        best = q;
        bestParts = parts;
      }
    }
    return Detection(
      quad: best == null ? null : _toFrame(best, gray.scale),
      confidence: bestParts,
      candidates: quads.length,
    );
  }

  List<List<Pt>> _edgeCandidates(
    Uint8List blurred,
    int w,
    int h,
    GradientField grad,
  ) {
    final edges = canny(blurred, w, h, grad);
    final closed = dilate3x3(edges, w, h);
    return hullsOfPieces(closed, w, h, minPixels: (w * h * 0.004).round());
  }

  List<List<Pt>> _brightnessCandidates(Uint8List blurred, int w, int h) {
    final out = <List<Pt>>[];
    final t1 = otsuThreshold(blurred);
    final t2 = otsuThreshold(blurred, above: t1);
    for (final t in {t1, t2}) {
      final mask = Uint8List(w * h);
      for (var i = 0; i < mask.length; i++) {
        mask[i] = blurred[i] > t ? 1 : 0;
      }
      final opened = erode3x3(dilate3x3(mask, w, h), w, h);
      out.addAll(
        hullsOfPieces(
          opened,
          w,
          h,
          minPixels: (w * h * minBrightFraction).round(),
        ),
      );
    }
    return out.take(maxCandidates * 2).toList();
  }
}

Quad _toFrame(Quad q, double scale) =>
    Quad([for (final p in q.p) Pt(p.x * scale, p.y * scale)]);

/// Canny edges: gradient, non-maximum suppression, hysteresis. The high
/// threshold is the 92nd percentile of the magnitude (clamped), the low one
/// 40% of it. Returns a 0/1 map.
Uint8List canny(Uint8List gray, int w, int h, GradientField grad) {
  final hi = grad.percentile(0.92).clamp(20, 120);
  final lo = (hi * 0.4).round();
  final mag = grad.mag;
  // Direction from the Sobel components, recomputed only where it matters.
  final thin = Uint8List(w * h);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final m = mag[i];
      if (m < lo) continue;
      final gx =
          (gray[i - w + 1] + 2 * gray[i + 1] + gray[i + w + 1]) -
          (gray[i - w - 1] + 2 * gray[i - 1] + gray[i + w - 1]);
      final gy =
          (gray[i + w - 1] + 2 * gray[i + w] + gray[i + w + 1]) -
          (gray[i - w - 1] + 2 * gray[i - w] + gray[i - w + 1]);
      final ax = gx.abs(), ay = gy.abs();
      int n1, n2;
      if (ay * 5 < ax * 2) {
        n1 = i - 1;
        n2 = i + 1; // horizontal gradient
      } else if (ax * 5 < ay * 2) {
        n1 = i - w;
        n2 = i + w; // vertical gradient
      } else if ((gx > 0) == (gy > 0)) {
        n1 = i - w - 1;
        n2 = i + w + 1;
      } else {
        n1 = i - w + 1;
        n2 = i + w - 1;
      }
      if (m >= mag[n1] && m >= mag[n2]) thin[i] = m >= hi ? 2 : 1;
    }
  }
  // Hysteresis: keep weak pixels that touch a strong one (8-neighbours).
  final out = Uint8List(w * h);
  final stack = <int>[];
  for (var i = 0; i < thin.length; i++) {
    if (thin[i] == 2) {
      out[i] = 1;
      stack.add(i);
    }
  }
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    final x = i % w, y = i ~/ w;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final j = ny * w + nx;
        if (thin[j] != 0 && out[j] == 0) {
          out[j] = 1;
          stack.add(j);
        }
      }
    }
  }
  return out;
}

Uint8List dilate3x3(Uint8List m, int w, int h) {
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = 0;
      for (var dy = -1; dy <= 1 && v == 0; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          if (nx >= 0 && nx < w && m[ny * w + nx] != 0) {
            v = 1;
            break;
          }
        }
      }
      out[y * w + x] = v;
    }
  }
  return out;
}

Uint8List erode3x3(Uint8List m, int w, int h) {
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = 1;
      for (var dy = -1; dy <= 1 && v == 1; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          if (nx >= 0 && nx < w && m[ny * w + nx] == 0) {
            v = 0;
            break;
          }
        }
      }
      out[y * w + x] = v;
    }
  }
  return out;
}

/// Connected pieces (8-neighbours) of a 0/1 map; for each piece with at least
/// [minPixels] pixels, the convex hull of the extreme pixels of every row and
/// column. Biggest first, at most [limit].
List<List<Pt>> hullsOfPieces(
  Uint8List m,
  int w,
  int h, {
  required int minPixels,
  int limit = 6,
}) {
  final seen = Uint8List(w * h);
  final pieces = <(int, List<Pt>)>[];
  final stack = <int>[];
  for (var start = 0; start < m.length; start++) {
    if (m[start] == 0 || seen[start] != 0) continue;
    final pix = <int>[];
    stack
      ..clear()
      ..add(start);
    seen[start] = 1;
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      pix.add(i);
      final x = i % w, y = i ~/ w;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final j = ny * w + nx;
          if (m[j] != 0 && seen[j] == 0) {
            seen[j] = 1;
            stack.add(j);
          }
        }
      }
    }
    final count = pix.length;
    if (count < minPixels) continue;
    final rowMin = List<int>.filled(h, w), rowMax = List<int>.filled(h, -1);
    final colMin = List<int>.filled(w, h), colMax = List<int>.filled(w, -1);
    for (final i in pix) {
      final x = i % w, y = i ~/ w;
      if (x < rowMin[y]) rowMin[y] = x;
      if (x > rowMax[y]) rowMax[y] = x;
      if (y < colMin[x]) colMin[x] = y;
      if (y > colMax[x]) colMax[x] = y;
    }
    final pts = <Pt>[];
    for (var y = 0; y < h; y++) {
      if (rowMax[y] >= 0) {
        pts.add(Pt(rowMin[y].toDouble(), y.toDouble()));
        pts.add(Pt(rowMax[y].toDouble(), y.toDouble()));
      }
    }
    for (var x = 0; x < w; x++) {
      if (colMax[x] >= 0) {
        pts.add(Pt(x.toDouble(), colMin[x].toDouble()));
        pts.add(Pt(x.toDouble(), colMax[x].toDouble()));
      }
    }
    pieces.add((count, convexHull(pts)));
  }
  pieces.sort((a, b) => b.$1.compareTo(a.$1));
  return [for (final p in pieces.take(math.max(1, limit))) p.$2];
}
