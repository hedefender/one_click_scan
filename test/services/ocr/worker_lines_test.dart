import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/services/ocr/paddle/worker_lines.dart';

/// One line as the worker sends it: text, confidence, row, eight corner
/// coordinates, and `[char, start, end, ...]`.
List<Object?> workerLine(
  String text, {
  double confidence = 0.97,
  int row = 0,
  List<Object?>? spans,
}) {
  final n = text.length;
  return [
    text,
    confidence,
    row,
    // top-left, top-right, bottom-right, bottom-left
    0.1, 0.2, 0.5, 0.2, 0.5, 0.3, 0.1, 0.3,
    spans ??
        [
          for (var i = 0; i < n; i++) ...[text[i], i / n, (i + 1) / n],
        ],
  ];
}

void main() {
  test('the stride is the number of fields of a line', () {
    expect(workerLine('ab'), hasLength(workerLineStride));
  });

  test('lines with their text, confidence, row and quad', () {
    final lines = linesFromWorker([
      ...workerLine('Total', confidence: 0.91, row: 3),
    ]);

    expect(lines, hasLength(1));
    expect(lines.single.text, 'Total');
    expect(lines.single.confidence, 0.91);
    expect(lines.single.row, 3);
    expect(lines.single.quad.map((p) => (p.x, p.y)), [
      (0.1, 0.2),
      (0.5, 0.2),
      (0.5, 0.3),
      (0.1, 0.3),
    ]);
    expect(lines.single.filtered, isFalse);
  });

  test('every character gets a box cut from the line box', () {
    final line = linesFromWorker(workerLine('ab cd')).single;

    final boxes = line.charBoxes!;
    expect(boxes.map((b) => b.character).join(), 'ab cd');
    // 5 characters over x 0.1..0.5: the third starts at 0.1 + 2 * 0.08.
    expect(boxes[2].quad[0].x, closeTo(0.26, 1e-9));
    expect(boxes[2].quad[1].x, closeTo(0.34, 1e-9));
    expect(boxes[2].quad[0].y, closeTo(0.2, 1e-9));
    expect(boxes[2].quad[3].y, closeTo(0.3, 1e-9));
    // The first starts at the left edge of the line, the last ends at the right.
    expect(boxes.first.quad[0].x, closeTo(0.1, 1e-9));
    expect(boxes.last.quad[1].x, closeTo(0.5, 1e-9));
  });

  test('Greek text with accents keeps its characters', () {
    final line = linesFromWorker(workerLine('Σύνολο')).single;

    expect(line.charBoxes!.map((b) => b.character), [
      'Σ',
      'ύ',
      'ν',
      'ο',
      'λ',
      'ο',
    ]);
  });

  test('several lines are read one after the other', () {
    final lines = linesFromWorker([
      ...workerLine('first', row: 0),
      ...workerLine('second', row: 1),
    ]);

    expect(lines.map((l) => l.text), ['first', 'second']);
    expect(lines.map((l) => l.row), [0, 1]);
  });

  test(
    'characters that do not add up to the text: no boxes, the line stays',
    () {
      final line = linesFromWorker(
        workerLine('abc', spans: ['a', 0.0, 0.5, 'x', 0.5, 1.0]),
      ).single;

      expect(line.text, 'abc');
      expect(line.charBoxes, isNull);
    },
  );

  test('no spans: no boxes, the line stays', () {
    final line = linesFromWorker(workerLine('abc', spans: <Object?>[])).single;

    expect(line.text, 'abc');
    expect(line.charBoxes, isNull);
  });

  test('a reply without lines gives an empty list', () {
    expect(linesFromWorker(const []), isEmpty);
  });

  test('a short tail (less than a whole line) is ignored', () {
    final lines = linesFromWorker([...workerLine('ok'), 'broken', 0.5]);

    expect(lines.map((l) => l.text), ['ok']);
  });
}
