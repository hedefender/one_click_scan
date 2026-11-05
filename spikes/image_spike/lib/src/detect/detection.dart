import 'dart:typed_data';

import '../geometry/quad.dart';

/// A picture as RGB bytes (3 per pixel, row by row).
class RgbFrame {
  const RgbFrame(this.width, this.height, this.rgb);

  final int width;
  final int height;
  final Uint8List rgb;
}

/// How sure a detection is, split into the parts that make it (each 0..1).
class ConfidenceParts {
  const ConfidenceParts({
    required this.area,
    required this.angle,
    required this.ratio,
    required this.support,
    required this.contrast,
  });

  static const none = ConfidenceParts(
    area: 0,
    angle: 0,
    ratio: 0,
    support: 0,
    contrast: 0,
  );

  /// The quad is a plausible share of the frame.
  final double area;

  /// The corners are near right angles (perspective allowed).
  final double angle;

  /// Opposite sides have similar lengths (perspective allowed).
  final double ratio;

  /// Share of the outline that lies on a real edge of the picture.
  final double support;

  /// The paper and what is outside differ along the outline.
  final double contrast;

  double get value {
    final geometry = [area, angle, ratio].reduce((a, b) => a < b ? a : b);
    return geometry * support * (0.5 + 0.5 * contrast);
  }

  Map<String, Object> toJson() => {
    'area': _r(area),
    'angle': _r(angle),
    'ratio': _r(ratio),
    'support': _r(support),
    'contrast': _r(contrast),
    'value': _r(value),
  };

  static double _r(double v) => double.parse(v.toStringAsFixed(3));
}

/// What a detector found in one frame. [quad] is in frame pixels and is the
/// best candidate whatever its confidence (null if there was no candidate);
/// the caller decides with a threshold whether to use it.
class Detection {
  const Detection({
    required this.quad,
    required this.confidence,
    required this.candidates,
    required this.microsPrepare,
    required this.microsDetect,
    required this.microsConfidence,
  });

  final Quad? quad;
  final ConfidenceParts confidence;
  final int candidates;
  final int microsPrepare;
  final int microsDetect;
  final int microsConfidence;

  double get score => quad == null ? 0 : confidence.value;

  int get microsTotal => microsPrepare + microsDetect + microsConfidence;
}

/// Finds the outline of a page in a frame.
abstract class DocumentDetector {
  String get name;

  Detection detect(RgbFrame frame);
}
