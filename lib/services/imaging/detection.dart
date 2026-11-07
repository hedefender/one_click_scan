import 'dart:typed_data';

import '../../domain/imaging/quad.dart';

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

  /// The weakest of the geometry parts, times the support of the edges, times
  /// the contrast (which counts for half).
  double get value {
    final geometry = [area, angle, ratio].reduce((a, b) => a < b ? a : b);
    return geometry * support * (0.5 + 0.5 * contrast);
  }
}

/// What the detector found in one frame. [quad] is in frame pixels and is the
/// best candidate whatever its confidence (null if there was no candidate);
/// the caller decides with `trustsDetection` whether to use it.
class Detection {
  const Detection({
    required this.quad,
    required this.confidence,
    required this.candidates,
  });

  final Quad? quad;
  final ConfidenceParts confidence;
  final int candidates;

  double get score => quad == null ? 0 : confidence.value;
}
