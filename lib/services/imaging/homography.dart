import '../../domain/imaging/quad.dart';

/// Row-major 3x3 homography from four point pairs ([src] to [dst]), with the
/// last element fixed to 1. Gaussian elimination with partial pivoting.
List<double> homographyFromPoints(List<Pt> src, List<Pt> dst) {
  assert(src.length == 4 && dst.length == 4);
  final a = List.generate(8, (_) => List<double>.filled(9, 0));
  for (var i = 0; i < 4; i++) {
    final x = src[i].x, y = src[i].y, u = dst[i].x, v = dst[i].y;
    a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u];
    a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v];
  }
  for (var c = 0; c < 8; c++) {
    var piv = c;
    for (var r = c + 1; r < 8; r++) {
      if (a[r][c].abs() > a[piv][c].abs()) piv = r;
    }
    if (a[piv][c].abs() < 1e-12) {
      throw ArgumentError('Degenerate point set for a homography');
    }
    final t = a[c];
    a[c] = a[piv];
    a[piv] = t;
    for (var r = 0; r < 8; r++) {
      if (r == c) continue;
      final f = a[r][c] / a[c][c];
      for (var k = c; k < 9; k++) {
        a[r][k] -= f * a[c][k];
      }
    }
  }
  return [for (var i = 0; i < 8; i++) a[i][8] / a[i][i], 1.0];
}

Pt applyHomography(List<double> h, Pt p) {
  final w = h[6] * p.x + h[7] * p.y + h[8];
  return Pt(
    (h[0] * p.x + h[1] * p.y + h[2]) / w,
    (h[3] * p.x + h[4] * p.y + h[5]) / w,
  );
}

List<double> invert3x3(List<double> m) {
  final a = m[0], b = m[1], c = m[2];
  final d = m[3], e = m[4], f = m[5];
  final g = m[6], h = m[7], i = m[8];
  final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
  if (det.abs() < 1e-18) throw ArgumentError('Singular matrix');
  final s = 1 / det;
  return [
    (e * i - f * h) * s,
    (c * h - b * i) * s,
    (b * f - c * e) * s,
    (f * g - d * i) * s,
    (a * i - c * g) * s,
    (c * d - a * f) * s,
    (d * h - e * g) * s,
    (b * g - a * h) * s,
    (a * e - b * d) * s,
  ];
}
