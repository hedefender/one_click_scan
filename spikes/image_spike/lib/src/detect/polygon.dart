import 'dart:math' as math;

import '../geometry/quad.dart';

double _cross(Pt o, Pt a, Pt b) =>
    (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);

/// Convex hull (Andrew's monotone chain). Result runs the same way as the
/// points are sorted: counter-clockwise on a y-up plane (clockwise on screen).
List<Pt> convexHull(List<Pt> points) {
  if (points.length < 3) return [...points];
  final p = [...points]
    ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  final lower = <Pt>[];
  for (final q in p) {
    while (lower.length >= 2 &&
        _cross(lower[lower.length - 2], lower.last, q) <= 0) {
      lower.removeLast();
    }
    lower.add(q);
  }
  final upper = <Pt>[];
  for (final q in p.reversed) {
    while (upper.length >= 2 &&
        _cross(upper[upper.length - 2], upper.last, q) <= 0) {
      upper.removeLast();
    }
    upper.add(q);
  }
  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}

Pt? _lineIntersection(Pt a1, Pt a2, Pt b1, Pt b2) {
  final d = (a1.x - a2.x) * (b1.y - b2.y) - (a1.y - a2.y) * (b1.x - b2.x);
  if (d.abs() < 1e-9) return null;
  final t = ((a1.x - b1.x) * (b1.y - b2.y) - (a1.y - b1.y) * (b1.x - b2.x)) / d;
  return Pt(a1.x + t * (a2.x - a1.x), a1.y + t * (a2.y - a1.y));
}

/// Reduces a convex polygon to four corners that **enclose** it: the two
/// vertices of the edge that costs the least extra area are replaced by the
/// point where the neighbouring edges meet. Nothing of the polygon is cut off.
/// Returns null for fewer than three points or a degenerate result.
Quad? enclosingQuad(List<Pt> hull) {
  if (hull.length < 3) return null;
  var poly = [...hull];
  if (poly.length == 3) {
    // A triangle has no fourth corner; the page cannot be seen as a quad.
    return null;
  }
  final cx = poly.map((e) => e.x).reduce((a, b) => a + b) / poly.length;
  final cy = poly.map((e) => e.y).reduce((a, b) => a + b) / poly.length;
  final centre = Pt(cx, cy);
  while (poly.length > 4) {
    final n = poly.length;
    int? bestK;
    Pt? bestPoint;
    var bestArea = double.infinity;
    for (var k = 0; k < n; k++) {
      final a = poly[(k - 1 + n) % n], b = poly[k];
      final c = poly[(k + 1) % n], d = poly[(k + 2) % n];
      final x = _lineIntersection(a, b, c, d);
      if (x == null) continue;
      // The meeting point must lie outside the edge b-c (away from the
      // centre), otherwise the lines diverge and the quad would shrink.
      final side = _cross(b, c, x);
      final centreSide = _cross(b, c, centre);
      if (side * centreSide >= 0) continue;
      final added = _cross(b, c, x).abs() / 2;
      if (added < bestArea) {
        bestArea = added;
        bestK = k;
        bestPoint = x;
      }
    }
    if (bestK == null) {
      // No clean merge (nearly parallel neighbours): drop the vertex that
      // changes the area least. This can cut a sliver; the confidence check
      // after it catches large losses.
      var minK = 0;
      var minArea = double.infinity;
      for (var k = 0; k < n; k++) {
        final area =
            _cross(poly[(k - 1 + n) % n], poly[k], poly[(k + 1) % n]).abs() / 2;
        if (area < minArea) {
          minArea = area;
          minK = k;
        }
      }
      poly = [...poly]..removeAt(minK);
      continue;
    }
    final k = bestK;
    final next = (k + 1) % n;
    final merged = <Pt>[];
    for (var i = 0; i < n; i++) {
      if (i == k) {
        merged.add(bestPoint!);
      } else if (i == next) {
        continue;
      } else {
        merged.add(poly[i]);
      }
    }
    poly = merged;
  }
  final q = Quad.ordered(poly);
  if (!q.isConvex || q.area < 1) return null;
  return q;
}

/// Smallest-area rectangle around the points is not needed here; this is the
/// bounding box as a quad, used only as a last resort for tests.
Quad boundingQuad(List<Pt> points) {
  final minX = points.map((p) => p.x).reduce(math.min);
  final maxX = points.map((p) => p.x).reduce(math.max);
  final minY = points.map((p) => p.y).reduce(math.min);
  final maxY = points.map((p) => p.y).reduce(math.max);
  return Quad([Pt(minX, minY), Pt(maxX, minY), Pt(maxX, maxY), Pt(minX, maxY)]);
}
