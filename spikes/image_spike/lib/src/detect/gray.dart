import 'dart:math' as math;
import 'dart:typed_data';

import 'detection.dart';

/// A grey picture at working size. [scale] is source pixels per working pixel.
class GrayImage {
  GrayImage(this.width, this.height, this.data, this.scale);

  final int width;
  final int height;
  final Uint8List data;
  final double scale;

  int at(int x, int y) => data[y * width + x];
}

/// Grey (Rec. 601 weights) and downscaled so the longer side is at most
/// [maxSide], by averaging the source pixels that fall in each target pixel.
GrayImage grayDownscaled(RgbFrame f, {int maxSide = 640}) {
  final longer = math.max(f.width, f.height);
  final scale = longer > maxSide ? longer / maxSide : 1.0;
  final tw = math.max(1, (f.width / scale).round());
  final th = math.max(1, (f.height / scale).round());
  final out = Uint8List(tw * th);
  final rgb = f.rgb;
  for (var ty = 0; ty < th; ty++) {
    final y0 = (ty * scale).floor();
    final y1 = math.min(f.height, math.max(y0 + 1, ((ty + 1) * scale).floor()));
    for (var tx = 0; tx < tw; tx++) {
      final x0 = (tx * scale).floor();
      final x1 = math.min(
        f.width,
        math.max(x0 + 1, ((tx + 1) * scale).floor()),
      );
      var sum = 0;
      var n = 0;
      for (var y = y0; y < y1; y++) {
        var o = (y * f.width + x0) * 3;
        for (var x = x0; x < x1; x++) {
          sum += rgb[o] * 299 + rgb[o + 1] * 587 + rgb[o + 2] * 114;
          o += 3;
          n++;
        }
      }
      out[ty * tw + tx] = (sum / (n * 1000)).round();
    }
  }
  return GrayImage(tw, th, out, scale);
}

int _hi(int a, int b) => a > b ? a : b;
int _lo(int a, int b) => a < b ? a : b;

/// Separable 5-tap binomial blur (1 4 6 4 1) / 16, borders replicated.
Uint8List gaussianBlur5(GrayImage g) {
  final w = g.width, h = g.height;
  final tmp = Uint16List(w * h);
  final src = g.data;
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      final xm2 = row + _hi(0, x - 2), xm1 = row + _hi(0, x - 1);
      final xp1 = row + _lo(w - 1, x + 1), xp2 = row + _lo(w - 1, x + 2);
      tmp[row + x] =
          src[xm2] + 4 * src[xm1] + 6 * src[row + x] + 4 * src[xp1] + src[xp2];
    }
  }
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final ym2 = _hi(0, y - 2) * w, ym1 = _hi(0, y - 1) * w;
    final yp1 = _lo(h - 1, y + 1) * w, yp2 = _lo(h - 1, y + 2) * w;
    final row = y * w;
    for (var x = 0; x < w; x++) {
      final v =
          tmp[ym2 + x] +
          4 * tmp[ym1 + x] +
          6 * tmp[row + x] +
          4 * tmp[yp1 + x] +
          tmp[yp2 + x];
      out[row + x] = (v + 128) ~/ 256;
    }
  }
  return out;
}

/// Otsu threshold of the pixels with value above [above] (use -1 for all).
int otsuThreshold(Uint8List data, {int above = -1}) {
  final hist = List<int>.filled(256, 0);
  var total = 0;
  for (final v in data) {
    if (v > above) {
      hist[v]++;
      total++;
    }
  }
  if (total == 0) return above < 0 ? 128 : above;
  var sumAll = 0.0;
  for (var i = 0; i < 256; i++) {
    sumAll += i * hist[i];
  }
  var wB = 0, sumB = 0.0, best = 0.0;
  var threshold = math.max(above, 0);
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB, mF = (sumAll - sumB) / wF;
    final between = wB.toDouble() * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      threshold = t;
    }
  }
  return threshold;
}
