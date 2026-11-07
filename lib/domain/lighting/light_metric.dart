import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// Brightness of a picture, from its Y (luma) level, 0..100.
///
/// The mean alone misleads (a page full of text is darker on average than an
/// empty one under the same light), so the metric is the **paper level** (95th
/// percentile: the white of the paper) and the **contrast** (95th minus 5th
/// percentile: paper against ink or dark background).
class LightMetric extends Equatable {
  const LightMetric({required this.paper, required this.contrast});

  /// 95th percentile of Y, 0..100.
  final double paper;

  /// 95th minus 5th percentile of Y, 0..100.
  final double contrast;

  /// From a grid of Y values (0..255). Every [stride]-th value is read, with
  /// the row structure [width] x [height] and [rowStride] bytes per row (the
  /// camera planes are padded). Null when nothing could be read.
  static LightMetric? fromLuma(
    Uint8List y, {
    required int width,
    required int height,
    int? rowStride,
    int stride = 1,
  }) {
    final pitch = rowStride ?? width;
    final histogram = List<int>.filled(256, 0);
    var count = 0;
    for (var row = 0; row < height; row += stride) {
      final base = row * pitch;
      for (var col = 0; col < width; col += stride) {
        final index = base + col;
        if (index >= y.length) break;
        histogram[y[index]]++;
        count++;
      }
    }
    if (count == 0) return null;
    final p95 = _percentile(histogram, count, 0.95);
    final p5 = _percentile(histogram, count, 0.05);
    return LightMetric(
      paper: p95 * 100 / 255,
      contrast: (p95 - p5) * 100 / 255,
    );
  }

  static int _percentile(List<int> histogram, int count, double q) {
    final target = (count * q).ceil().clamp(1, count);
    var seen = 0;
    for (var level = 0; level < 256; level++) {
      seen += histogram[level];
      if (seen >= target) return level;
    }
    return 255;
  }

  @override
  List<Object?> get props => [paper, contrast];

  @override
  String toString() =>
      'LightMetric(paper ${paper.toStringAsFixed(1)}, '
      'contrast ${contrast.toStringAsFixed(1)})';
}
