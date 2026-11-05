import 'dart:math' as math;
import 'dart:typed_data';

import '../detect/detection.dart';

/// Contrast and shadow options for the page picture (request 4). Pure Dart,
/// on an upright [RgbFrame]; each one returns a new frame.

Uint8List lumaOf(RgbFrame f) {
  final n = f.width * f.height;
  final y = Uint8List(n);
  final p = f.rgb;
  for (var i = 0, j = 0; i < n; i++, j += 3) {
    y[i] = (p[j] * 299 + p[j + 1] * 587 + p[j + 2] * 114) ~/ 1000;
  }
  return y;
}

RgbFrame _fromLuma(Uint8List y, int w, int h) {
  final out = Uint8List(w * h * 3);
  for (var i = 0, j = 0; i < y.length; i++, j += 3) {
    out[j] = out[j + 1] = out[j + 2] = y[i];
  }
  return RgbFrame(w, h, out);
}

/// Grey, no other change.
RgbFrame toGray(RgbFrame f) => _fromLuma(lumaOf(f), f.width, f.height);

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
  final (g, gw, gh, cell) = _background(lumaOf(f), w, h);
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

/// Contrast limited adaptive histogram equalisation of the brightness, with
/// the colour ratio kept (like OpenCV's CLAHE on the L channel).
RgbFrame clahe(RgbFrame f, {int tiles = 8, double clip = 2.0}) {
  final w = f.width, h = f.height;
  final y = lumaOf(f);
  final tw = (w + tiles - 1) ~/ tiles, th = (h + tiles - 1) ~/ tiles;
  final maps = List.generate(tiles * tiles, (_) => Uint8List(256));
  for (var ty = 0; ty < tiles; ty++) {
    for (var tx = 0; tx < tiles; tx++) {
      final hist = List<int>.filled(256, 0);
      final y0 = ty * th, y1 = math.min(h, y0 + th);
      final x0 = tx * tw, x1 = math.min(w, x0 + tw);
      for (var yy = y0; yy < y1; yy++) {
        for (var xx = x0; xx < x1; xx++) {
          hist[y[yy * w + xx]]++;
        }
      }
      final area = math.max(1, (y1 - y0) * (x1 - x0));
      final limit = math.max(1, (clip * area / 256).round());
      var excess = 0;
      for (var i = 0; i < 256; i++) {
        if (hist[i] > limit) {
          excess += hist[i] - limit;
          hist[i] = limit;
        }
      }
      final add = excess ~/ 256;
      var cum = 0;
      final map = maps[ty * tiles + tx];
      for (var i = 0; i < 256; i++) {
        cum += hist[i] + add;
        map[i] = math.min(255, (cum * 255 / area).round());
      }
    }
  }
  final out = Uint8List(f.rgb.length);
  final src = f.rgb;
  for (var yy = 0; yy < h; yy++) {
    final fy = (yy + 0.5) / th - 0.5;
    final ty0 = fy.floor().clamp(0, tiles - 1),
        ty1 = math.min(tiles - 1, ty0 + 1);
    final wy = (fy - ty0).clamp(0.0, 1.0);
    for (var xx = 0; xx < w; xx++) {
      final fx = (xx + 0.5) / tw - 0.5;
      final tx0 = fx.floor().clamp(0, tiles - 1),
          tx1 = math.min(tiles - 1, tx0 + 1);
      final wx = (fx - tx0).clamp(0.0, 1.0);
      final v = y[yy * w + xx];
      final a =
          maps[ty0 * tiles + tx0][v] * (1 - wx) +
          maps[ty0 * tiles + tx1][v] * wx;
      final b =
          maps[ty1 * tiles + tx0][v] * (1 - wx) +
          maps[ty1 * tiles + tx1][v] * wx;
      final nv = a * (1 - wy) + b * wy;
      final ratio = v == 0 ? 1.0 : nv / v;
      final i = (yy * w + xx) * 3;
      if (v == 0) {
        out[i] = out[i + 1] = out[i + 2] = nv.round().clamp(0, 255);
      } else {
        out[i] = math.min(255, (src[i] * ratio).round());
        out[i + 1] = math.min(255, (src[i + 1] * ratio).round());
        out[i + 2] = math.min(255, (src[i + 2] * ratio).round());
      }
    }
  }
  return RgbFrame(w, h, out);
}

/// Black and white by a local mean threshold (integral image): a pixel is ink
/// when it is more than [bias] below the mean of its neighbourhood.
RgbFrame binarize(RgbFrame f, {double bias = 0.10}) {
  final w = f.width, h = f.height;
  final y = lumaOf(f);
  final iw = w + 1;
  final integral = Float64List(iw * (h + 1));
  for (var yy = 0; yy < h; yy++) {
    var row = 0.0;
    for (var xx = 0; xx < w; xx++) {
      row += y[yy * w + xx];
      integral[(yy + 1) * iw + xx + 1] = integral[yy * iw + xx + 1] + row;
    }
  }
  final r = math.max(15, math.max(w, h) ~/ 40);
  final out = Uint8List(w * h);
  for (var yy = 0; yy < h; yy++) {
    final y0 = math.max(0, yy - r), y1 = math.min(h, yy + r + 1);
    for (var xx = 0; xx < w; xx++) {
      final x0 = math.max(0, xx - r), x1 = math.min(w, xx + r + 1);
      final sum =
          integral[y1 * iw + x1] -
          integral[y0 * iw + x1] -
          integral[y1 * iw + x0] +
          integral[y0 * iw + x0];
      final mean = sum / ((y1 - y0) * (x1 - x0));
      out[yy * w + xx] = y[yy * w + xx] < mean * (1 - bias) ? 0 : 255;
    }
  }
  return _fromLuma(out, w, h);
}

/// The named options of the evaluation.
typedef Enhancer = RgbFrame Function(RgbFrame);

final Map<String, Enhancer> enhancers = {
  'color': (f) => f,
  'gray': toGray,
  'flat': flattenLight,
  'clahe': clahe,
  'flat+clahe': (f) => clahe(flattenLight(f)),
  'binary': (f) => binarize(flattenLight(f)),
};
