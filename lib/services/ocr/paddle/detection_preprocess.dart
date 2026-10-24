import 'dart:typed_data';

import 'paddle_constants.dart';
import 'pixels.dart';

/// The detection tensor `[1, 3, dh, dw]` (planes B, G, R, normalised): the
/// image resized bilinearly to [dw] x [dh]. Typed lists only, no allocation
/// per pixel.
Float32List detectionInput(Pixels p, int dw, int dh) {
  final w = p.w, h = p.h, s = p.stride, d = p.data;
  final plane = dw * dh;
  final out = Float32List(3 * plane);
  final sx = w / dw, sy = h / dh;

  // Column tables: byte offsets of the two neighbours and the weight.
  final xa = Int32List(dw), xb = Int32List(dw);
  final fxs = Float64List(dw);
  for (var x = 0; x < dw; x++) {
    final f = (x + 0.5) * sx - 0.5;
    final i = f.floor();
    fxs[x] = f - i;
    xa[x] = (i < 0 ? 0 : (i > w - 1 ? w - 1 : i)) * s;
    final j = i + 1;
    xb[x] = (j < 0 ? 0 : (j > w - 1 ? w - 1 : j)) * s;
  }

  // value * k + b  ==  (value / 255 - mean) / std
  const mean = PaddleConstants.detMean, std = PaddleConstants.detStd;
  final kB = 1 / (255 * std[0]), bB = -mean[0] / std[0];
  final kG = 1 / (255 * std[1]), bG = -mean[1] / std[1];
  final kR = 1 / (255 * std[2]), bR = -mean[2] / std[2];

  for (var y = 0; y < dh; y++) {
    final f = (y + 0.5) * sy - 0.5;
    final i = f.floor();
    final fy = f - i;
    final ya = (i < 0 ? 0 : (i > h - 1 ? h - 1 : i)) * w * s;
    final j = i + 1;
    final yb = (j < 0 ? 0 : (j > h - 1 ? h - 1 : j)) * w * s;
    final ofs = y * dw;
    for (var x = 0; x < dw; x++) {
      final fx = fxs[x];
      final a = ya + xa[x], b = ya + xb[x], c = yb + xa[x], e = yb + xb[x];
      final r =
          (d[a] * (1 - fx) + d[b] * fx) * (1 - fy) +
          (d[c] * (1 - fx) + d[e] * fx) * fy;
      final g =
          (d[a + 1] * (1 - fx) + d[b + 1] * fx) * (1 - fy) +
          (d[c + 1] * (1 - fx) + d[e + 1] * fx) * fy;
      final bl =
          (d[a + 2] * (1 - fx) + d[b + 2] * fx) * (1 - fy) +
          (d[c + 2] * (1 - fx) + d[e + 2] * fx) * fy;
      final o = ofs + x;
      out[o] = bl * kB + bB;
      out[plane + o] = g * kG + bG;
      out[2 * plane + o] = r * kR + bR;
    }
  }
  return out;
}
