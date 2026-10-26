import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import '../entities/ocr_line.dart';
import 'pdf_config.dart';

/// One piece of hidden text, in PDF user space (points, origin bottom-left,
/// y up).
class PdfTextRun extends Equatable {
  const PdfTextRun({
    required this.text,
    required this.x,
    required this.y,
    required this.angle,
    required this.fontSize,
    required this.width,
  });

  final String text;

  /// Start of the baseline.
  final double x;
  final double y;

  /// Counter-clockwise, radians (PDF orientation).
  final double angle;
  final double fontSize;

  /// The width the text has to occupy on the page, in points. The writer
  /// stretches the text to it with horizontal scaling, so a word covers the
  /// place of the printed word whatever the font.
  final double width;

  @override
  List<Object?> get props => [text, x, y, angle, fontSize, width];
}

/// Size of a PDF page in points for a picture of [widthPx] x [heightPx].
({double width, double height}) pageSizeFor(int widthPx, int heightPx) {
  const k = PdfConfig.pointsPerInch / PdfConfig.dpi;
  return (width: widthPx * k, height: heightPx * k);
}

/// The hidden text of one page: one run per word (ADR-016).
///
/// Only lines that passed the confidence filter are used. A line whose
/// characters are known is cut into words at its spaces and each word takes the
/// place of its own characters; a line without character boxes (or whose
/// boxes do not add up to its text) becomes one run for the whole line.
List<PdfTextRun> layoutPageText({
  required List<OcrLine> lines,
  required int imageWidth,
  required int imageHeight,
}) {
  final runs = <PdfTextRun>[];
  for (final line in lines) {
    if (line.filtered) continue;
    final words = _wordsOf(line);
    for (final (text, quad) in words) {
      final run = _runFor(text, quad, imageWidth, imageHeight);
      if (run != null) runs.add(run);
    }
  }
  return runs;
}

/// (word text, word quad) pairs of one line.
List<(String, List<OcrPoint>)> _wordsOf(OcrLine line) {
  final boxes = line.charBoxes;
  final joined = boxes?.map((b) => b.character).join();
  if (boxes == null || boxes.isEmpty || joined != line.text) {
    return [(line.text, line.quad)];
  }
  final words = <(String, List<OcrPoint>)>[];
  var first = -1;
  void close(int lastIndex) {
    if (first < 0) return;
    final text = boxes
        .sublist(first, lastIndex + 1)
        .map((b) => b.character)
        .join();
    final a = boxes[first].quad;
    final b = boxes[lastIndex].quad;
    // From the left edge of the first character to the right edge of the last.
    words.add((text, [a[0], b[1], b[2], a[3]]));
    first = -1;
  }

  for (var i = 0; i < boxes.length; i++) {
    if (boxes[i].character.trim().isEmpty) {
      close(i - 1);
    } else if (first < 0) {
      first = i;
    }
  }
  close(boxes.length - 1);
  return words;
}

PdfTextRun? _runFor(
  String text,
  List<OcrPoint> quad,
  int imageWidth,
  int imageHeight,
) {
  if (text.trim().isEmpty) return null;
  // Corners in pixels of the working copy.
  double px(OcrPoint p) => p.x * imageWidth;
  double py(OcrPoint p) => p.y * imageHeight;
  final tlx = px(quad[0]), tly = py(quad[0]);
  final dx = px(quad[1]) - tlx, dy = py(quad[1]) - tly;
  final vx = px(quad[3]) - tlx, vy = py(quad[3]) - tly;
  final width = math.sqrt(dx * dx + dy * dy);
  final height = math.sqrt(vx * vx + vy * vy);
  if (width < PdfConfig.minBoxPixels || height < PdfConfig.minBoxPixels) {
    return null;
  }

  const k = PdfConfig.pointsPerInch / PdfConfig.dpi;
  final pageHeight = imageHeight * k;
  // The baseline starts below the top-left corner, along the box's own down
  // direction (so a tilted line keeps its tilt).
  const down = 1 - PdfConfig.baselineFromBottom;
  final bx = tlx + vx * down;
  final by = tly + vy * down;
  return PdfTextRun(
    text: text,
    x: bx * k,
    y: pageHeight - by * k,
    angle: -math.atan2(dy, dx),
    fontSize: height * PdfConfig.fontHeightShare * k,
    width: width * k,
  );
}
