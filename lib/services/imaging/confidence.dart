import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/imaging/quad.dart';
import 'detection.dart';
import 'gray.dart';

double _smoothstep(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Sobel gradient magnitude of the working picture, scaled to 0..255
/// ((|gx| + |gy|) / 4, so a step of d grey levels gives about d).
class GradientField {
  GradientField(this.width, this.height, this.mag, this.p99);

  final int width;
  final int height;
  final Uint8List mag;

  /// The 99th percentile of the magnitude (a scale for "strong edge").
  final int p99;

  factory GradientField.of(Uint8List gray, int width, int height) {
    final mag = Uint8List(width * height);
    final hist = List<int>.filled(256, 0);
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final i = y * width + x;
        final a = gray[i - width - 1],
            b = gray[i - width],
            c = gray[i - width + 1];
        final d = gray[i - 1], f = gray[i + 1];
        final g = gray[i + width - 1],
            h = gray[i + width],
            k = gray[i + width + 1];
        final gx = (c + 2 * f + k) - (a + 2 * d + g);
        final gy = (g + 2 * h + k) - (a + 2 * b + c);
        final m = math.min(255, (gx.abs() + gy.abs()) ~/ 4);
        mag[i] = m;
        hist[m]++;
      }
    }
    final total = (width - 2) * (height - 2);
    var acc = 0;
    var p99 = 255;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= total * 0.99) {
        p99 = v;
        break;
      }
    }
    return GradientField(width, height, mag, p99);
  }

  /// Magnitude value at the given percentile (0..1).
  int percentile(double p) {
    final hist = List<int>.filled(256, 0);
    for (final v in mag) {
      hist[v]++;
    }
    final total = mag.length;
    var acc = 0;
    for (var v = 0; v < 256; v++) {
      acc += hist[v];
      if (acc >= total * p) return v;
    }
    return 255;
  }
}

/// Scores a candidate outline (in working-picture pixels). Pure geometry plus
/// two looks at the picture along the outline: is there an edge there, and is
/// the paper on the inside different from what is outside.
ConfidenceParts scoreQuad(
  Quad q,
  GrayImage gray,
  GradientField grad, {
  double areaLow = 0.05,
  double areaHigh = 0.2,
}) {
  if (!q.isConvex) return ConfidenceParts.none;
  final w = gray.width, h = gray.height;
  final frameArea = (w * h).toDouble();
  final ratioOfFrame = q.area / frameArea;
  final area =
      _smoothstep(areaLow, areaHigh, ratioOfFrame) *
      (1 - _smoothstep(0.97, 1.0, ratioOfFrame));

  var worst = 0.0;
  for (final a in q.anglesDeg) {
    worst = math.max(worst, (a - 90).abs());
  }
  final angle = 1 - _smoothstep(25, 50, worst);

  final r1 =
      math.min(q.topWidth, q.bottomWidth) / math.max(q.topWidth, q.bottomWidth);
  final r2 =
      math.min(q.leftHeight, q.rightHeight) /
      math.max(q.leftHeight, q.rightHeight);
  final ratio = _smoothstep(0.45, 0.7, math.min(r1, r2));

  // Walk along the four sides.
  final cx = q.p.map((e) => e.x).reduce((a, b) => a + b) / 4;
  final cy = q.p.map((e) => e.y).reduce((a, b) => a + b) / 4;
  final thr = (0.25 * grad.p99).clamp(8, 40).toDouble();
  var samples = 0;
  var supported = 0;
  final diffs = <double>[];
  for (var s = 0; s < 4; s++) {
    final a = q.p[s], b = q.p[(s + 1) % 4];
    final len = a.distanceTo(b);
    if (len < 4) continue;
    var nx = -(b.y - a.y) / len, ny = (b.x - a.x) / len;
    // Make the normal point away from the centre.
    final mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
    if ((mx - cx) * nx + (my - cy) * ny < 0) {
      nx = -nx;
      ny = -ny;
    }
    final steps = math.max(8, (len / 3).round());
    for (var i = 0; i < steps; i++) {
      final t = (i + 0.5) / steps;
      final px = a.x + (b.x - a.x) * t, py = a.y + (b.y - a.y) * t;
      // A sample near the border of the picture is not judged: the page
      // may simply continue outside the frame.
      if (px < 6 || py < 6 || px > w - 7 || py > h - 7) continue;
      samples++;
      var best = 0;
      for (var k = -3; k <= 3; k++) {
        final sx = (px + nx * k).round(), sy = (py + ny * k).round();
        if (sx < 1 || sy < 1 || sx >= w - 1 || sy >= h - 1) continue;
        best = math.max(best, grad.mag[sy * w + sx]);
      }
      if (best >= thr) supported++;
      final ix = (px - nx * 5).round().clamp(0, w - 1);
      final iy = (py - ny * 5).round().clamp(0, h - 1);
      final ox = (px + nx * 5).round().clamp(0, w - 1);
      final oy = (py + ny * 5).round().clamp(0, h - 1);
      diffs.add((gray.at(ix, iy) - gray.at(ox, oy)).abs().toDouble());
    }
  }
  if (samples < 8) {
    return ConfidenceParts(
      area: area,
      angle: angle,
      ratio: ratio,
      support: 0,
      contrast: 0,
    );
  }
  final support = _smoothstep(0.5, 0.9, supported / samples);
  diffs.sort();
  final median = diffs[diffs.length ~/ 2];
  final contrast = _smoothstep(6, 26, median);
  return ConfidenceParts(
    area: area,
    angle: angle,
    ratio: ratio,
    support: support,
    contrast: contrast,
  );
}
