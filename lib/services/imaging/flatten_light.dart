import 'dart:math' as math;
import 'dart:typed_data';

import 'detection.dart';

/// Shadow and uneven light removal (`flat`), moved from the spike
/// `spikes/image_spike/lib/src/image/enhance.dart` (ADR-030). Pure Dart, on an
/// upright [RgbFrame]; it only ever runs because the user asked for it, in a
/// background isolate (`IsolateLightEnhancer`).

Uint8List _lumaOf(RgbFrame f) {
  final n = f.width * f.height;
  final y = Uint8List(n);
  final p = f.rgb;
  for (var i = 0, j = 0; i < n; i++, j += 3) {
    y[i] = (p[j] * 299 + p[j + 1] * 587 + p[j + 2] * 114) ~/ 1000;
  }
  return y;
}

/// The paper's own brightness across the picture (light and shadow), at a
/// coarse grid: the maximum of each cell drops the text, a wider maximum and a
/// blur smooth it. Returns the grid and its size.
(Float32List, int, int, int) _background(Uint8List y, int w, int h) {
  final cell = math.max(8, math.max(w, h) ~/ 120);
  final gw = (w + cell - 1) ~/ cell, gh = (h + cell - 1) ~/ cell;
  var g = Float32List(gw * gh);
  for (var cy = 0; cy < gh; cy++) {
    for (var cx = 0; cx < gw; cx++) {
      var m = 0;
      final y1 = math.min(h, (cy + 1) * cell),
          x1 = math.min(w, (cx + 1) * cell);
      for (var yy = cy * cell; yy < y1; yy++) {
        final row = yy * w;
        for (var xx = cx * cell; xx < x1; xx++) {
          if (y[row + xx] > m) m = y[row + xx];
        }
      }
      g[cy * gw + cx] = m.toDouble();
    }
  }
  g = _maxFilter(g, gw, gh, 1);
  for (var k = 0; k < 2; k++) {
    g = _boxBlur(g, gw, gh, 2);
  }
  return (g, gw, gh, cell);
}

Float32List _maxFilter(Float32List g, int gw, int gh, int r) {
  final out = Float32List(g.length);
  for (var y = 0; y < gh; y++) {
    for (var x = 0; x < gw; x++) {
      var m = 0.0;
      for (var yy = math.max(0, y - r); yy <= math.min(gh - 1, y + r); yy++) {
        for (var xx = math.max(0, x - r); xx <= math.min(gw - 1, x + r); xx++) {
          final v = g[yy * gw + xx];
          if (v > m) m = v;
        }
      }
      out[y * gw + x] = m;
    }
  }
  return out;
}

Float32List _boxBlur(Float32List g, int gw, int gh, int r) {
  final out = Float32List(g.length);
  for (var y = 0; y < gh; y++) {
    for (var x = 0; x < gw; x++) {
      var s = 0.0;
      var c = 0;
      for (var yy = math.max(0, y - r); yy <= math.min(gh - 1, y + r); yy++) {
        for (var xx = math.max(0, x - r); xx <= math.min(gw - 1, x + r); xx++) {
          s += g[yy * gw + xx];
          c++;
        }
      }
      out[y * gw + x] = s / c;
    }
  }
  return out;
}

/// Shadow and uneven light removal: every pixel is divided by the paper's
/// local brightness, so the paper becomes white and the text keeps its
/// contrast; the colour is kept (all three channels get the same gain).
RgbFrame flattenLight(RgbFrame f) {
  final w = f.width, h = f.height;
  final (g, gw, gh, cell) = _background(_lumaOf(f), w, h);
  final out = Uint8List(f.rgb.length);
  final src = f.rgb;
  // Bilinear lookup of the background between cell centres.
  for (var y = 0; y < h; y++) {
    final fy = (y + 0.5) / cell - 0.5;
    final y0 = fy.floor().clamp(0, gh - 1), y1 = math.min(gh - 1, y0 + 1);
    final ty = (fy - y0).clamp(0.0, 1.0);
    for (var x = 0; x < w; x++) {
      final fx = (x + 0.5) / cell - 0.5;
      final x0 = fx.floor().clamp(0, gw - 1), x1 = math.min(gw - 1, x0 + 1);
      final tx = (fx - x0).clamp(0.0, 1.0);
      final top = g[y0 * gw + x0] * (1 - tx) + g[y0 * gw + x1] * tx;
      final bot = g[y1 * gw + x0] * (1 - tx) + g[y1 * gw + x1] * tx;
      final bg = math.max(40.0, top * (1 - ty) + bot * ty);
      final gain = 255 / bg;
      final i = (y * w + x) * 3;
      out[i] = math.min(255, (src[i] * gain).round());
      out[i + 1] = math.min(255, (src[i + 1] * gain).round());
      out[i + 2] = math.min(255, (src[i + 2] * gain).round());
    }
  }
  return RgbFrame(w, h, out);
}
