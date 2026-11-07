import 'dart:math' as math;
import 'dart:typed_data';

import 'detection.dart';
import 'homography.dart';
import '../../domain/imaging/quad.dart';

/// The width over the height the page really has, from how its four corners
/// look and the camera's focal length in pixels [focalPx] (a real app gets it
/// from the EXIF 35 mm focal length). The outline is the image of a unit
/// square, so the first two columns of its homography, seen through the
/// camera matrix, have lengths in the proportion of the sides. The principal
/// point is [cx], [cy] and the pixels are square. Null when [focalPx] is not
/// positive or the result is implausible.
double? aspectFromFocal(Quad q, double focalPx, double cx, double cy) {
  if (focalPx <= 0) return null;
  try {
    final h = homographyFromPoints(
      const [Pt(0, 0), Pt(1, 0), Pt(1, 1), Pt(0, 1)],
      [for (final p in q.p) Pt(p.x - cx, p.y - cy)],
    );
    double len(double x, double y, double z) => math.sqrt(
      (x / focalPx) * (x / focalPx) + (y / focalPx) * (y / focalPx) + z * z,
    );
    final ratio = len(h[0], h[3], h[6]) / len(h[1], h[4], h[7]);
    if (!ratio.isFinite || ratio < 0.2 || ratio > 5) return null;
    return ratio;
  } on ArgumentError {
    return null;
  }
}

/// Size of the upright picture for an outline. With a focal length the picture
/// has the page's real proportions and is at least as large as the outline's
/// sides; without one it takes the mean of opposite sides (a tilted page then
/// comes out narrower than it is). The longer side is capped at [maxSide].
(int, int) rectifiedSize(
  Quad q, {
  int maxSide = 2560,
  double? cx,
  double? cy,
  double focalPx = 0,
}) {
  var w = (q.topWidth + q.bottomWidth) / 2;
  var h = (q.leftHeight + q.rightHeight) / 2;
  final aspect = cx == null || cy == null
      ? null
      : aspectFromFocal(q, focalPx, cx, cy);
  if (aspect != null) {
    final byWidth = w * (w / aspect);
    final byHeight = (h * aspect) * h;
    if (byWidth >= byHeight) {
      h = w / aspect;
    } else {
      w = h * aspect;
    }
  }
  final longer = math.max(w, h);
  if (longer > maxSide) {
    final s = maxSide / longer;
    w *= s;
    h *= s;
  }
  return (math.max(1, w.round()), math.max(1, h.round()));
}

/// A3: the picture inside [q] seen from the front, in plain Dart (inverse
/// mapping with bilinear sampling).
RgbFrame warpToQuadDart(
  RgbFrame src,
  Quad q, {
  int maxSide = 2560,
  double focalPx = 0,
}) {
  final (w, h) = rectifiedSize(
    q,
    maxSide: maxSide,
    cx: src.width / 2,
    cy: src.height / 2,
    focalPx: focalPx,
  );
  final dstRect = [
    const Pt(0, 0),
    Pt(w.toDouble(), 0),
    Pt(w.toDouble(), h.toDouble()),
    Pt(0, h.toDouble()),
  ];
  // Destination pixel -> source position.
  final hm = homographyFromPoints(dstRect, q.p);
  final out = Uint8List(w * h * 3);
  final sw = src.width, sh = src.height;
  final rgb = src.rgb;
  var o = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final px = x + 0.5, py = y + 0.5;
      final d = hm[6] * px + hm[7] * py + hm[8];
      final sx = ((hm[0] * px + hm[1] * py + hm[2]) / d - 0.5).clamp(
        0.0,
        sw - 1.001,
      );
      final sy = ((hm[3] * px + hm[4] * py + hm[5]) / d - 0.5).clamp(
        0.0,
        sh - 1.001,
      );
      final ix = sx.toInt(), iy = sy.toInt();
      final fx = sx - ix, fy = sy - iy;
      final i00 = (iy * sw + ix) * 3;
      final i10 = i00 + 3;
      final i01 = i00 + sw * 3;
      final i11 = i01 + 3;
      for (var c = 0; c < 3; c++) {
        final top = rgb[i00 + c] * (1 - fx) + rgb[i10 + c] * fx;
        final bottom = rgb[i01 + c] * (1 - fx) + rgb[i11 + c] * fx;
        out[o++] = (top * (1 - fy) + bottom * fy + 0.5).toInt();
      }
    }
  }
  return RgbFrame(w, h, out);
}
