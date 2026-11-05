import '../../../domain/entities/ocr_line.dart';
import '../../../domain/ocr/char_boxes.dart';

/// Number of values per line in the flat `lines` list of a worker result:
/// text, confidence, row, eight corner coordinates, and a list with the
/// character, start and end (fractions of the box length) of each character.
const workerLineStride = 12;

/// The lines of a worker reply (`lines` in the layout above).
List<OcrLine> linesFromWorker(List<Object?> flat) {
  final lines = <OcrLine>[];
  for (var i = 0; i + workerLineStride <= flat.length; i += workerLineStride) {
    final quad = [
      for (var k = 0; k < 4; k++)
        OcrPoint(
          (flat[i + 3 + 2 * k]! as num).toDouble(),
          (flat[i + 4 + 2 * k]! as num).toDouble(),
        ),
    ];
    final text = flat[i]! as String;
    lines.add(
      OcrLine(
        text: text,
        confidence: (flat[i + 1]! as num).toDouble(),
        row: flat[i + 2]! as int,
        quad: quad,
        charBoxes: _charBoxes(quad, text, flat[i + 11]! as List),
      ),
    );
  }
  return lines;
}

/// Character boxes from the worker's `[char, start, end, ...]` list, or null
/// when the characters do not add up to the line's text (the PDF then uses the
/// whole line).
List<OcrCharBox>? _charBoxes(
  List<OcrPoint> quad,
  String text,
  List<Object?> flat,
) {
  final spans = <CharSpan>[];
  final joined = StringBuffer();
  for (var k = 0; k + 3 <= flat.length; k += 3) {
    final character = flat[k]! as String;
    joined.write(character);
    spans.add(
      CharSpan(
        character,
        (flat[k + 1]! as num).toDouble(),
        (flat[k + 2]! as num).toDouble(),
      ),
    );
  }
  if (spans.isEmpty || joined.toString() != text) return null;
  return charBoxesFromSpans(quad, spans);
}
