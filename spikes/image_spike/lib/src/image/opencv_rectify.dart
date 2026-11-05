import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../detect/detection.dart';
import '../geometry/quad.dart';
import 'rectify.dart';

/// A1: the picture inside [q] seen from the front, with OpenCV
/// (getPerspectiveTransform and warpPerspective, bilinear).
RgbFrame warpToQuadOpenCv(
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
  final srcMat = cv.Mat.fromVec(
    cv.VecU8.fromList(src.rgb),
    rows: src.height,
    cols: src.width,
    type: cv.MatType.CV_8UC3,
  );
  final from = cv.VecPoint2f.fromList([
    for (final p in q.p) cv.Point2f(p.x, p.y),
  ]);
  final to = cv.VecPoint2f.fromList([
    cv.Point2f(0, 0),
    cv.Point2f(w.toDouble(), 0),
    cv.Point2f(w.toDouble(), h.toDouble()),
    cv.Point2f(0, h.toDouble()),
  ]);
  final m = cv.getPerspectiveTransform2f(from, to);
  final out = cv.warpPerspective(srcMat, m, (w, h), flags: cv.INTER_LINEAR);
  final bytes = Uint8List.fromList(out.data);
  srcMat.dispose();
  from.dispose();
  to.dispose();
  m.dispose();
  out.dispose();
  return RgbFrame(w, h, bytes);
}
