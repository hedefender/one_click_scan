import '../entities/ocr_line.dart';

/// Where one recognised character sits along its text box, as fractions 0..1
/// of the box length (left end of the text = 0). Derived from the CTC time step
/// at which the character was emitted, so it costs no extra inference.
class CharSpan {
  const CharSpan(this.character, this.start, this.end);

  final String character;
  final double start;
  final double end;
}

/// The part of [quad] between the fractions [start] and [end] of its length.
///
/// [quad] is a text box: top-left, top-right, bottom-right, bottom-left. The
/// box is a (rotated) rectangle, so every corner of the slice is a linear
/// interpolation along the top and the bottom edge.
List<OcrPoint> sliceQuad(List<OcrPoint> quad, double start, double end) {
  assert(quad.length == 4, 'a quad has four corners');
  final from = start.clamp(0.0, 1.0);
  final to = end.clamp(0.0, 1.0);
  OcrPoint along(OcrPoint a, OcrPoint b, double t) =>
      OcrPoint(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
  return [
    along(quad[0], quad[1], from),
    along(quad[0], quad[1], to),
    along(quad[3], quad[2], to),
    along(quad[3], quad[2], from),
  ];
}

/// One [OcrCharBox] per span, each with its slice of the line's [quad].
List<OcrCharBox> charBoxesFromSpans(
  List<OcrPoint> quad,
  Iterable<CharSpan> spans,
) {
  return [
    for (final span in spans)
      OcrCharBox(
        character: span.character,
        quad: sliceQuad(quad, span.start, span.end),
      ),
  ];
}
