import 'dart:math' as math;

import 'paddle_constants.dart';

/// A rotated rectangle around one piece of text, in pixels of the image.
class TextBox {
  TextBox(this.cx, this.cy, this.w, this.h, this.angle);

  /// Centre, width along the text, height across it, and the angle of the
  /// text direction in radians (-pi/2..pi/2, left to right).
  final double cx, cy, w, h, angle;

  /// Reading row, set by `sortBoxes`.
  int row = -1;

  TextBox scaled(double sx, double sy) {
    // The two factors are the same resize ratio up to rounding, so one
    // average is enough for the box size.
    final s = (sx + sy) / 2;
    return TextBox(cx * sx, cy * sy, w * s, h * s, angle);
  }

  /// Width of the recognition crop (48 px high) for this box.
  int get cropWidth => math.min(
    PaddleConstants.maxRecWidth,
    math.max(
      PaddleConstants.minRecWidth,
      (PaddleConstants.recHeight * (w / h)).round(),
    ),
  );

  /// The four corners in image pixels: top-left, top-right, bottom-right,
  /// bottom-left of the text box (rotated with the text).
  List<(double, double)> corners() {
    final ux = math.cos(angle), uy = math.sin(angle);
    (double, double) corner(double u, double v) =>
        (cx + u * ux - v * uy, cy + u * uy + v * ux);
    final hw = w / 2, hh = h / 2;
    return [corner(-hw, -hh), corner(hw, -hh), corner(hw, hh), corner(-hw, hh)];
  }
}

/// Detection input size: longest side limited to [side], both sides rounded
/// to a multiple of [PaddleConstants.detMultiple] (at least one multiple).
(int, int) detDims(int w, int h, int side) {
  final scale = math.min(1.0, side / math.max(w, h));
  const m = PaddleConstants.detMultiple;
  int round(double v) => math.max(m, (v / m).round() * m);
  return (round(w * scale), round(h * scale));
}
