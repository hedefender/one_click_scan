import 'dart:math' as math;
import 'dart:typed_data';

import 'paddle_constants.dart';
import 'text_box.dart';

/// DB post-processing of the probability map `[dh, dw]`: connected regions
/// above the threshold become rotated boxes, grown back by the unclip ratio,
/// scaled by [toX] and [toY] to the pixels of the image and put in reading
/// order. Typed lists and a breadth-first queue; every pixel enters once.
List<TextBox> boxesFromMap(
  Float32List prob,
  int w,
  int h,
  double toX,
  double toY,
) {
  final n = w * h;
  final seen = Uint8List(n);
  // A component is the slice [from, tail) of the queue, so no per-component
  // lists are needed.
  final queue = Int32List(n);
  var tail = 0;
  final boxes = <TextBox>[];
  for (var start = 0; start < n; start++) {
    if (seen[start] != 0 || prob[start] <= PaddleConstants.detThreshold) {
      continue;
    }
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
          if (seen[q] == 0 && prob[q] > PaddleConstants.detThreshold) {
            seen[q] = 1;
            queue[tail++] = q;
          }
        }
      }
    }
    final count = tail - from;
    if (count < PaddleConstants.minRegionPixels) continue;
    if (sum / count < PaddleConstants.boxThreshold) continue;
    final box = _orientedBox(queue, from, tail, w);
    if (math.min(box.w, box.h) < PaddleConstants.minBoxSide) continue;
    boxes.add(_unclip(box).scaled(toX, toY));
  }
  return sortBoxes(boxes);
}

/// Unclip: grow the shrunk text kernel back (DB post-processing).
TextBox _unclip(TextBox box) {
  final d = box.w * box.h * PaddleConstants.unclipRatio / (2 * (box.w + box.h));
  return TextBox(box.cx, box.cy, box.w + 2 * d, box.h + 2 * d, box.angle);
}

/// Minimum-area style box from the principal axes of the region's pixels.
TextBox _orientedBox(Int32List q, int from, int to, int w) {
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

  var angle = 0.5 * math.atan2(2 * cxy, cxx - cyy);
  var ux = math.cos(angle), uy = math.sin(angle);
  var umin = 1e9, umax = -1e9, vmin = 1e9, vmax = -1e9;
  for (var i = from; i < to; i++) {
    final p = q[i];
    final y = p ~/ w;
    final dx = (p - y * w) - mx, dy = y - my;
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
  // Keep the text direction left to right.
  while (angle > math.pi / 2) {
    angle -= math.pi;
  }
  while (angle < -math.pi / 2) {
    angle += math.pi;
  }
  return TextBox(cx + 0.5, cy + 0.5, umax - umin + 1, vmax - vmin + 1, angle);
}

/// Reading order: rows first, then left to right inside a row. The rows are
/// measured perpendicular to the median text direction, so a page tilted by a
/// few degrees still groups its lines correctly. Sets [TextBox.row].
List<TextBox> sortBoxes(List<TextBox> boxes) {
  final angles = [
    for (final b in boxes)
      if (b.w > 2 * b.h) b.angle,
  ]..sort();
  final skew = angles.isEmpty ? 0.0 : angles[angles.length ~/ 2];
  final cs = math.cos(skew), sn = math.sin(skew);
  double perp(TextBox b) => -b.cx * sn + b.cy * cs;
  double along(TextBox b) => b.cx * cs + b.cy * sn;
  boxes.sort((a, b) => perp(a).compareTo(perp(b)));
  final rows = <List<TextBox>>[];
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
