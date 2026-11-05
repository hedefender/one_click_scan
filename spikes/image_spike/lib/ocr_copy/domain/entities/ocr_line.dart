import 'package:equatable/equatable.dart';

/// A point in an image, both coordinates 0..1 of the upright working image
/// (x across the width, y down the height).
class OcrPoint extends Equatable {
  const OcrPoint(this.x, this.y);

  final double x;
  final double y;

  @override
  List<Object?> get props => [x, y];
}

/// Box of one recognised character: its slice of the line's box, from the CTC
/// time step at which the character was emitted (Phase 3, for the text layer
/// of the PDF).
class OcrCharBox extends Equatable {
  const OcrCharBox({required this.character, required this.quad});

  final String character;
  final List<OcrPoint> quad;

  @override
  List<Object?> get props => [character, quad];
}

/// One text segment as the detector found it (usually a line, sometimes part
/// of one when the gap between words is large).
class OcrLine extends Equatable {
  const OcrLine({
    required this.text,
    required this.confidence,
    required this.quad,
    this.row = 0,
    this.filtered = false,
    this.charBoxes,
  }) : assert(quad.length == 4, 'a quad has four corners');

  /// Text exactly as recognised. The scanner never edits it.
  final String text;

  /// 0..1, mean of the per-character probabilities.
  final double confidence;

  /// Corners in the order top-left, top-right, bottom-right, bottom-left of
  /// the text box (rotated with the text, so a tilted line is not widened).
  final List<OcrPoint> quad;

  /// Reading row. Segments with the same row belong to one visual line.
  final int row;

  /// Set when the confidence is below the threshold. The line stays in the
  /// result; only the visible text leaves it out.
  final bool filtered;

  /// One box per character of [text], in order (spaces included), or null when
  /// the engine could not place them. The PDF then uses the whole line.
  final List<OcrCharBox>? charBoxes;

  OcrLine copyWith({bool? filtered}) => OcrLine(
    text: text,
    confidence: confidence,
    quad: quad,
    row: row,
    filtered: filtered ?? this.filtered,
    charBoxes: charBoxes,
  );

  @override
  List<Object?> get props => [text, confidence, quad, row, filtered, charBoxes];
}
