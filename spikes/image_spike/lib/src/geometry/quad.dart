import 'dart:math' as math;

/// A point in pixel coordinates (x right, y down).
class Pt {
  const Pt(this.x, this.y);

  final double x;
  final double y;

  double distanceTo(Pt o) =>
      math.sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y));

  @override
  String toString() => 'Pt(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)})';
}

/// Signed area (shoelace). Positive when the points run clockwise on screen
/// (y down).
double signedArea(List<Pt> p) {
  var s = 0.0;
  for (var i = 0; i < p.length; i++) {
    final a = p[i];
    final b = p[(i + 1) % p.length];
    s += a.x * b.y - b.x * a.y;
  }
  return s / 2;
}

double polygonArea(List<Pt> p) => p.length < 3 ? 0 : signedArea(p).abs();

/// A four-sided page outline, ordered top-left, top-right, bottom-right,
/// bottom-left.
class Quad {
  const Quad(this.p) : assert(p.length == 4);

  final List<Pt> p;

  /// Orders any four points as TL, TR, BR, BL (by angle around the centre,
  /// starting from the point with the smallest x + y).
  factory Quad.ordered(List<Pt> pts) {
    assert(pts.length == 4);
    final cx = pts.map((e) => e.x).reduce((a, b) => a + b) / 4;
    final cy = pts.map((e) => e.y).reduce((a, b) => a + b) / 4;
    final sorted = [...pts]
      ..sort(
        (a, b) => math
            .atan2(a.y - cy, a.x - cx)
            .compareTo(math.atan2(b.y - cy, b.x - cx)),
      );
    // Angles ascend clockwise on screen (y down). Start at the top-left.
    var start = 0;
    for (var i = 1; i < 4; i++) {
      if (sorted[i].x + sorted[i].y < sorted[start].x + sorted[start].y) {
        start = i;
      }
    }
    return Quad([for (var i = 0; i < 4; i++) sorted[(start + i) % 4]]);
  }

  /// The whole frame as a quad.
  factory Quad.frame(int width, int height) => Quad([
    const Pt(0, 0),
    Pt(width.toDouble(), 0),
    Pt(width.toDouble(), height.toDouble()),
    Pt(0, height.toDouble()),
  ]);

  double get area => polygonArea(p);

  bool get isConvex {
    var sign = 0;
    for (var i = 0; i < 4; i++) {
      final a = p[i];
      final b = p[(i + 1) % 4];
      final c = p[(i + 2) % 4];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cross.abs() < 1e-9) continue;
      final s = cross > 0 ? 1 : -1;
      if (sign == 0) sign = s;
      if (s != sign) return false;
    }
    return true;
  }

  double get topWidth => p[0].distanceTo(p[1]);
  double get bottomWidth => p[3].distanceTo(p[2]);
  double get leftHeight => p[0].distanceTo(p[3]);
  double get rightHeight => p[1].distanceTo(p[2]);

  /// The four inner angles, in degrees.
  List<double> get anglesDeg {
    final out = <double>[];
    for (var i = 0; i < 4; i++) {
      final a = p[(i + 3) % 4];
      final b = p[i];
      final c = p[(i + 1) % 4];
      final v1x = a.x - b.x, v1y = a.y - b.y;
      final v2x = c.x - b.x, v2y = c.y - b.y;
      final cos =
          (v1x * v2x + v1y * v2y) /
          (math.sqrt(v1x * v1x + v1y * v1y) * math.sqrt(v2x * v2x + v2y * v2y));
      out.add(math.acos(cos.clamp(-1.0, 1.0)) * 180 / math.pi);
    }
    return out;
  }

  Map<String, Object> toJson() => {
    'points': [
      for (final q in p)
        [
          double.parse(q.x.toStringAsFixed(2)),
          double.parse(q.y.toStringAsFixed(2)),
        ],
    ],
  };

  factory Quad.fromJson(Map<String, Object?> json) {
    final pts = (json['points']! as List)
        .map(
          (e) =>
              Pt(((e as List)[0] as num).toDouble(), (e[1] as num).toDouble()),
        )
        .toList();
    return Quad(pts);
  }
}

/// Sutherland-Hodgman clipping of [subject] by the convex polygon [clip].
List<Pt> clipPolygon(List<Pt> subject, List<Pt> clip) {
  if (subject.length < 3 || clip.length < 3) return const [];
  final clipPts = signedArea(clip) >= 0 ? clip : clip.reversed.toList();
  var output = subject;
  for (var i = 0; i < clipPts.length; i++) {
    final a = clipPts[i];
    final b = clipPts[(i + 1) % clipPts.length];
    bool inside(Pt q) =>
        (b.x - a.x) * (q.y - a.y) - (b.y - a.y) * (q.x - a.x) >= 0;
    Pt intersect(Pt s, Pt e) {
      final den = (s.x - e.x) * (a.y - b.y) - (s.y - e.y) * (a.x - b.x);
      if (den.abs() < 1e-12) return e;
      final t = ((s.x - a.x) * (a.y - b.y) - (s.y - a.y) * (a.x - b.x)) / den;
      return Pt(s.x + t * (e.x - s.x), s.y + t * (e.y - s.y));
    }

    final input = output;
    output = [];
    if (input.isEmpty) break;
    var s = input.last;
    for (final e in input) {
      if (inside(e)) {
        if (!inside(s)) output.add(intersect(s, e));
        output.add(e);
      } else if (inside(s)) {
        output.add(intersect(s, e));
      }
      s = e;
    }
  }
  return output;
}

/// Intersection over union of two convex quads.
double quadIou(Quad a, Quad b) {
  final inter = polygonArea(clipPolygon(a.p, b.p));
  final union = a.area + b.area - inter;
  return union <= 0 ? 0 : inter / union;
}

/// Share of [truth] that lies inside [detected]. 1.0 means nothing of the true
/// page was cut off: the number that matters for "no information lost".
double coverageOfTruth(Quad detected, Quad truth) {
  if (truth.area <= 0) return 0;
  return polygonArea(clipPolygon(truth.p, detected.p)) / truth.area;
}

/// Mean distance of the four corners as a percentage of the frame diagonal.
/// Both quads must be ordered the same way (TL, TR, BR, BL).
double cornerErrorPct(Quad detected, Quad truth, double frameDiagonal) {
  var s = 0.0;
  for (var i = 0; i < 4; i++) {
    s += detected.p[i].distanceTo(truth.p[i]);
  }
  return s / 4 / frameDiagonal * 100;
}
