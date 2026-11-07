import 'package:one_click_scan/domain/imaging/quad.dart';

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
