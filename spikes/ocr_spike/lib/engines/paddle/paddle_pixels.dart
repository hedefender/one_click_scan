import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect, Offset;

/// Pixel maths around the two PP-OCRv5 networks. Every step has two forms:
/// the `*Legacy` one is the Phase 1.5 code unchanged (allocates a list per
/// sampled pixel, boxes every number) and the `*Fast` one does the same
/// arithmetic on typed lists. They are kept side by side so the experiment can
/// time the same input through both.

const recHeight = 48;
const maxRecWidth = 2048;
const detThresh = 0.3;
const boxThresh = 0.6;
const unclipRatio = 1.5;

/// Interleaved 8-bit pixels, [stride] bytes per pixel (3 = RGB, 4 = RGBA).
class Pixels {
  const Pixels(this.data, this.w, this.h, this.stride);
  final Uint8List data;
  final int w, h, stride;
}

class PBox {
  PBox(this.cx, this.cy, this.w, this.h, this.angle);
  final double cx, cy, w, h, angle;

  /// Reading row, set by [sortBoxes].
  int row = -1;

  PBox scaled(double sx, double sy) {
    // Anisotropic scale on a rotated box: keep it simple, the two factors are
    // equal in practice (both are the same resize ratio up to rounding).
    final s = (sx + sy) / 2;
    return PBox(cx * sx, cy * sy, w * s, h * s, angle);
  }

  Rect get bounds {
    final c = math.cos(angle).abs(), s = math.sin(angle).abs();
    final bw = w * c + h * s, bh = w * s + h * c;
    return Rect.fromCenter(center: Offset(cx, cy), width: bw, height: bh);
  }

  /// Width of the 48 px high recognition crop.
  int get cropWidth =>
      math.min(maxRecWidth, math.max(16, (recHeight * (w / h)).round()));
}

/// Detection input size: longest side limited to [side], both sides rounded
/// to a multiple of 32.
(int, int) detDims(int w, int h, int side) {
  final scale = math.min(1.0, side / math.max(w, h));
  int round32(double v) => math.max(32, (v / 32).round() * 32);
  return (round32(w * scale), round32(h * scale));
}

// ------------------------------------------------------------ detection input

const _mean = [0.406, 0.456, 0.485]; // B, G, R
const _std = [0.225, 0.224, 0.229];

Float32List detInputLegacy(Pixels p, int dw, int dh) {
  final w = p.w, h = p.h;
  final input = Float32List(3 * dh * dw);
  final sx = w / dw, sy = h / dh;
  for (var y = 0; y < dh; y++) {
    for (var x = 0; x < dw; x++) {
      final px = _sample(p, (x + 0.5) * sx - 0.5, (y + 0.5) * sy - 0.5);
      final o = y * dw + x;
      input[o] = (px[2] / 255 - _mean[0]) / _std[0];
      input[dh * dw + o] = (px[1] / 255 - _mean[1]) / _std[1];
      input[2 * dh * dw + o] = (px[0] / 255 - _mean[2]) / _std[2];
    }
  }
  return input;
}

Float32List detInputFast(Pixels p, int dw, int dh) {
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
  final kB = 1 / (255 * _std[0]), bB = -_mean[0] / _std[0];
  final kG = 1 / (255 * _std[1]), bG = -_mean[1] / _std[1];
  final kR = 1 / (255 * _std[2]), bR = -_mean[2] / _std[2];
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

// ---------------------------------------------------------- detection output

List<PBox> boxesFromMapLegacy(
  Float32List prob,
  int w,
  int h,
  double toX,
  double toY,
) {
  final seen = Uint8List(w * h);
  final stack = Int32List(w * h);
  final boxes = <PBox>[];
  for (var start = 0; start < prob.length; start++) {
    if (seen[start] != 0 || prob[start] <= detThresh) continue;
    var sp = 0;
    stack[sp++] = start;
    seen[start] = 1;
    final xs = <int>[];
    final ys = <int>[];
    var sum = 0.0;
    while (sp > 0) {
      final p = stack[--sp];
      final px = p % w, py = p ~/ w;
      xs.add(px);
      ys.add(py);
      sum += prob[p];
      for (var dy = -1; dy <= 1; dy++) {
        final ny = py + dy;
        if (ny < 0 || ny >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = px + dx;
          if (nx < 0 || nx >= w) continue;
          final q = ny * w + nx;
          if (seen[q] == 0 && prob[q] > detThresh) {
            seen[q] = 1;
            stack[sp++] = q;
          }
        }
      }
    }
    if (xs.length < 12) continue;
    if (sum / xs.length < boxThresh) continue;
    final box = _orientedBox(xs, ys);
    if (math.min(box.w, box.h) < 3) continue;
    boxes.add(_unclip(box).scaled(toX, toY));
  }
  return sortBoxes(boxes);
}

List<PBox> boxesFromMapFast(
  Float32List prob,
  int w,
  int h,
  double toX,
  double toY,
) {
  final n = w * h;
  final seen = Uint8List(n);
  // Breadth-first queue; each pixel enters once, so a component is the slice
  // [from, tail) and no per-component lists are needed.
  final queue = Int32List(n);
  var tail = 0;
  final boxes = <PBox>[];
  for (var start = 0; start < n; start++) {
    if (seen[start] != 0 || prob[start] <= detThresh) continue;
    final from = tail;
    var head = tail;
    queue[tail++] = start;
    seen[start] = 1;
    var sum = 0.0;
    while (head < tail) {
      final p = queue[head++];
      final py = p ~/ w, px = p - py * w;
      sum += prob[p];
      final y0 = py > 0 ? py - 1 : 0, y1 = py < h - 1 ? py + 1 : h - 1;
      final x0 = px > 0 ? px - 1 : 0, x1 = px < w - 1 ? px + 1 : w - 1;
      for (var ny = y0; ny <= y1; ny++) {
        final row = ny * w;
        for (var nx = x0; nx <= x1; nx++) {
          final q = row + nx;
          if (seen[q] == 0 && prob[q] > detThresh) {
            seen[q] = 1;
            queue[tail++] = q;
          }
        }
      }
    }
    final count = tail - from;
    if (count < 12) continue;
    if (sum / count < boxThresh) continue;
    final box = _orientedBoxQueue(queue, from, tail, w);
    if (math.min(box.w, box.h) < 3) continue;
    boxes.add(_unclip(box).scaled(toX, toY));
  }
  return sortBoxes(boxes);
}

/// Unclip: grow the shrunk text kernel back (DB post-processing).
PBox _unclip(PBox box) {
  final d = box.w * box.h * unclipRatio / (2 * (box.w + box.h));
  return PBox(box.cx, box.cy, box.w + 2 * d, box.h + 2 * d, box.angle);
}

PBox _orientedBox(List<int> xs, List<int> ys) {
  final n = xs.length;
  var mx = 0.0, my = 0.0;
  for (var i = 0; i < n; i++) {
    mx += xs[i];
    my += ys[i];
  }
  mx /= n;
  my /= n;
  var cxx = 0.0, cyy = 0.0, cxy = 0.0;
  for (var i = 0; i < n; i++) {
    final dx = xs[i] - mx, dy = ys[i] - my;
    cxx += dx * dx;
    cyy += dy * dy;
    cxy += dx * dy;
  }
  return _boxFromMoments(
    mx,
    my,
    cxx,
    cyy,
    cxy,
    n,
    (i) => xs[i] - mx,
    (i) => ys[i] - my,
  );
}

PBox _orientedBoxQueue(Int32List q, int from, int to, int w) {
  final n = to - from;
  var mx = 0.0, my = 0.0;
  for (var i = from; i < to; i++) {
    final p = q[i];
    final y = p ~/ w;
    mx += p - y * w;
    my += y;
  }
  mx /= n;
  my /= n;
  var cxx = 0.0, cyy = 0.0, cxy = 0.0;
  for (var i = from; i < to; i++) {
    final p = q[i];
    final y = p ~/ w;
    final dx = (p - y * w) - mx, dy = y - my;
    cxx += dx * dx;
    cyy += dy * dy;
    cxy += dx * dy;
  }
  return _boxFromMoments(mx, my, cxx, cyy, cxy, n, (i) {
    final p = q[from + i];
    return (p - (p ~/ w) * w) - mx;
  }, (i) => (q[from + i] ~/ w) - my);
}

PBox _boxFromMoments(
  double mx,
  double my,
  double cxx,
  double cyy,
  double cxy,
  int n,
  double Function(int) dxOf,
  double Function(int) dyOf,
) {
  var angle = 0.5 * math.atan2(2 * cxy, cxx - cyy);
  var ux = math.cos(angle), uy = math.sin(angle);
  var umin = 1e9, umax = -1e9, vmin = 1e9, vmax = -1e9;
  for (var i = 0; i < n; i++) {
    final dx = dxOf(i), dy = dyOf(i);
    final u = dx * ux + dy * uy;
    final v = -dx * uy + dy * ux;
    umin = math.min(umin, u);
    umax = math.max(umax, u);
    vmin = math.min(vmin, v);
    vmax = math.max(vmax, v);
  }
  // Make "u" the long axis: rotate by 90 degrees. The new u axis is the old
  // v axis, the new v axis is the old u axis with its sign flipped.
  if (vmax - vmin > umax - umin) {
    angle += math.pi / 2;
    ux = math.cos(angle);
    uy = math.sin(angle);
    final (oumin, oumax) = (umin, umax);
    umin = vmin;
    umax = vmax;
    vmin = -oumax;
    vmax = -oumin;
  }
  final cu = (umin + umax) / 2, cv = (vmin + vmax) / 2;
  final cx = mx + cu * ux - cv * uy;
  final cy = my + cu * uy + cv * ux;
  // Keep text direction left to right.
  while (angle > math.pi / 2) {
    angle -= math.pi;
  }
  while (angle < -math.pi / 2) {
    angle += math.pi;
  }
  return PBox(cx + 0.5, cy + 0.5, umax - umin + 1, vmax - vmin + 1, angle);
}

/// Reading order: rows first, then left to right inside a row. The rows are
/// measured perpendicular to the median text direction, so a page tilted by
/// a few degrees still groups its lines correctly.
List<PBox> sortBoxes(List<PBox> boxes) {
  final angles = [
    for (final b in boxes)
      if (b.w > 2 * b.h) b.angle,
  ]..sort();
  final skew = angles.isEmpty ? 0.0 : angles[angles.length ~/ 2];
  final cs = math.cos(skew), sn = math.sin(skew);
  double perp(PBox b) => -b.cx * sn + b.cy * cs;
  double along(PBox b) => b.cx * cs + b.cy * sn;
  boxes.sort((a, b) => perp(a).compareTo(perp(b)));
  final rows = <List<PBox>>[];
  for (final b in boxes) {
    if (rows.isNotEmpty) {
      final ref = rows.last.first;
      if ((perp(b) - perp(ref)).abs() < 0.5 * math.min(b.h, ref.h)) {
        rows.last.add(b);
        b.row = rows.length - 1;
        continue;
      }
    }
    rows.add([b]);
    b.row = rows.length - 1;
  }
  return [
    for (final r in rows) ...(r..sort((a, b) => along(a).compareTo(along(b)))),
  ];
}

// ------------------------------------------------------------------- crops

/// Warps the rotated box into a [recHeight] high patch (planes B, G, R,
/// `(x/255 - 0.5) / 0.5`).
Float32List cropLegacy(Pixels p, PBox box) {
  final outW = box.cropWidth;
  final out = Float32List(3 * recHeight * outW);
  final ux = math.cos(box.angle), uy = math.sin(box.angle);
  for (var y = 0; y < recHeight; y++) {
    final v = ((y + 0.5) / recHeight - 0.5) * box.h;
    for (var x = 0; x < outW; x++) {
      final u = ((x + 0.5) / outW - 0.5) * box.w;
      final px = box.cx + u * ux - v * uy - 0.5;
      final py = box.cy + u * uy + v * ux - 0.5;
      final c = _sample(p, px, py);
      final o = y * outW + x;
      out[o] = c[2] / 127.5 - 1;
      out[recHeight * outW + o] = c[1] / 127.5 - 1;
      out[2 * recHeight * outW + o] = c[0] / 127.5 - 1;
    }
  }
  return out;
}

/// Same warp, written into a batch tensor: item starts at [base], planes are
/// [planeW] wide (>= the crop width, the rest stays 0).
void cropInto(Pixels p, PBox box, Float32List out, int base, int planeW) {
  final outW = box.cropWidth;
  final w = p.w, h = p.h, s = p.stride, d = p.data;
  final ux = math.cos(box.angle), uy = math.sin(box.angle);
  final plane = recHeight * planeW;
  const k = 1 / 127.5;
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

/// Copies a legacy crop (planes [outW] wide) into a batch tensor.
void copyCropInto(
  Float32List crop,
  int outW,
  Float32List out,
  int base,
  int planeW,
) {
  for (var c = 0; c < 3; c++) {
    for (var y = 0; y < recHeight; y++) {
      final src = (c * recHeight + y) * outW;
      final dst = base + (c * recHeight + y) * planeW;
      out.setRange(dst, dst + outW, crop, src);
    }
  }
}

List<double> _sample(Pixels p, double x, double y) {
  final w = p.w, h = p.h, s = p.stride, d = p.data;
  final x0 = x.floor(), y0 = y.floor();
  final fx = x - x0, fy = y - y0;
  int cl(int v, int hi) => v < 0 ? 0 : (v > hi ? hi : v);
  final xa = cl(x0, w - 1), xb = cl(x0 + 1, w - 1);
  final ya = cl(y0, h - 1), yb = cl(y0 + 1, h - 1);
  final out = [0.0, 0.0, 0.0];
  for (var c = 0; c < 3; c++) {
    final v00 = d[(ya * w + xa) * s + c];
    final v10 = d[(ya * w + xb) * s + c];
    final v01 = d[(yb * w + xa) * s + c];
    final v11 = d[(yb * w + xb) * s + c];
    out[c] =
        (v00 * (1 - fx) + v10 * fx) * (1 - fy) +
        (v01 * (1 - fx) + v11 * fx) * fy;
  }
  return out;
}

// ---------------------------------------------------------------- CTC decode

/// Greedy CTC over item [item] of a `[B, T, C]` output, using only the first
/// [steps] time steps (the rest is padding of a wider batch member).
(String, double) ctcLegacy(
  List<dynamic> flat,
  int item,
  int t,
  int classes,
  int steps,
  List<String> dict,
) {
  final buffer = StringBuffer();
  var last = 0;
  var confSum = 0.0, confCount = 0;
  final off = item * t * classes;
  for (var s = 0; s < steps; s++) {
    var best = 0;
    var bestP = -1.0;
    final base = off + s * classes;
    for (var c = 0; c < classes; c++) {
      final p = (flat[base + c] as num).toDouble();
      if (p > bestP) {
        bestP = p;
        best = c;
      }
    }
    if (best != 0 && best != last) {
      if (best < dict.length) buffer.write(dict[best]);
      confSum += bestP;
      confCount++;
    }
    last = best;
  }
  return (buffer.toString(), confCount == 0 ? 0.0 : confSum / confCount);
}

/// CTC over the argmax variant: `[B,T]` class indices and probabilities.
(String, double) ctcArgmax(
  List<dynamic> idx,
  List<dynamic> prob,
  int item,
  int t,
  int steps,
  List<String> dict,
) {
  final buffer = StringBuffer();
  var last = 0;
  var confSum = 0.0, confCount = 0;
  final off = item * t;
  for (var s = 0; s < steps; s++) {
    final best = idx[off + s] as int;
    if (best != 0 && best != last) {
      if (best < dict.length) buffer.write(dict[best]);
      confSum += (prob[off + s] as num).toDouble();
      confCount++;
    }
    last = best;
  }
  return (buffer.toString(), confCount == 0 ? 0.0 : confSum / confCount);
}

(String, double) ctcFast(
  Float32List flat,
  int item,
  int t,
  int classes,
  int steps,
  List<String> dict,
) {
  final buffer = StringBuffer();
  var last = 0;
  var confSum = 0.0, confCount = 0;
  final off = item * t * classes;
  for (var s = 0; s < steps; s++) {
    var best = 0;
    var bestP = flat[off + s * classes];
    final base = off + s * classes;
    for (var c = 1; c < classes; c++) {
      final p = flat[base + c];
      if (p > bestP) {
        bestP = p;
        best = c;
      }
    }
    if (best != 0 && best != last) {
      if (best < dict.length) buffer.write(dict[best]);
      confSum += bestP;
      confCount++;
    }
    last = best;
  }
  return (buffer.toString(), confCount == 0 ? 0.0 : confSum / confCount);
}
