import 'dart:math' as math;
import 'dart:typed_data';

import 'paddle_constants.dart';
import 'pixels.dart';
import 'text_box.dart';

/// Warps the rotated [box] into a 48 px high patch and writes it into [out]
/// (planes B, G, R, `value / 127.5 - 1`). The item starts at [base]; planes are
/// [planeW] wide (at least the crop width, the rest stays 0).
void cropInto(Pixels p, TextBox box, Float32List out, int base, int planeW) {
  const recHeight = PaddleConstants.recHeight;
  final outW = box.cropWidth;
  final w = p.w, h = p.h, s = p.stride, d = p.data;
  final ux = math.cos(box.angle), uy = math.sin(box.angle);
  final plane = recHeight * planeW;
  const k = PaddleConstants.recScale;
  final rowStride = w * s;
  for (var y = 0; y < recHeight; y++) {
    final v = ((y + 0.5) / recHeight - 0.5) * box.h;
    final vx = -v * uy, vy = v * ux;
    final ofs = base + y * planeW;
    for (var x = 0; x < outW; x++) {
      final u = ((x + 0.5) / outW - 0.5) * box.w;
      final fxp = box.cx + u * ux + vx - 0.5;
      final fyp = box.cy + u * uy + vy - 0.5;
      final xf = fxp.floor(), yf = fyp.floor();
      final fx = fxp - xf, fy = fyp - yf;
      final xa = (xf < 0 ? 0 : (xf > w - 1 ? w - 1 : xf)) * s;
      final xb = (xf + 1 < 0 ? 0 : (xf + 1 > w - 1 ? w - 1 : xf + 1)) * s;
      final ya = (yf < 0 ? 0 : (yf > h - 1 ? h - 1 : yf)) * rowStride;
      final yb =
          (yf + 1 < 0 ? 0 : (yf + 1 > h - 1 ? h - 1 : yf + 1)) * rowStride;
      final a = ya + xa, b = ya + xb, c = yb + xa, e = yb + xb;
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
      out[o] = bl * k - 1;
      out[plane + o] = g * k - 1;
      out[2 * plane + o] = r * k - 1;
    }
  }
}
