import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/ocr_line.dart';
import 'package:one_click_scan/domain/ocr/char_boxes.dart';

void main() {
  // A box 0.4 wide and 0.1 high with its corner at (0.2, 0.3).
  const quad = [
    OcrPoint(0.2, 0.3),
    OcrPoint(0.6, 0.3),
    OcrPoint(0.6, 0.4),
    OcrPoint(0.2, 0.4),
  ];

  group('sliceQuad', () {
    test('the whole box is the box itself', () {
      expect(sliceQuad(quad, 0, 1), quad);
    });

    test('a middle part keeps the height and cuts the width', () {
      final slice = sliceQuad(quad, 0.25, 0.75);

      expect(slice[0].x, closeTo(0.3, 1e-9));
      expect(slice[1].x, closeTo(0.5, 1e-9));
      expect(slice[2].x, closeTo(0.5, 1e-9));
      expect(slice[3].x, closeTo(0.3, 1e-9));
      expect([slice[0].y, slice[1].y], [0.3, 0.3]);
      expect(slice[2].y, closeTo(0.4, 1e-9));
    });

    test('a tilted box is cut along its own direction', () {
      // Rotated 45 degrees: the top edge runs from (0, 0) to (0.2, 0.2).
      const tilted = [
        OcrPoint(0, 0),
        OcrPoint(0.2, 0.2),
        OcrPoint(0.15, 0.25),
        OcrPoint(-0.05, 0.05),
      ];

      final slice = sliceQuad(tilted, 0.5, 1);

      expect(slice[0].x, closeTo(0.1, 1e-9));
      expect(slice[0].y, closeTo(0.1, 1e-9));
      expect(slice[1].x, closeTo(0.2, 1e-9));
      expect(slice[2].x, closeTo(0.15, 1e-9));
      expect(slice[3].x, closeTo(0.05, 1e-9));
      expect(slice[3].y, closeTo(0.15, 1e-9));
    });

    test('fractions outside 0..1 are clamped to the box', () {
      expect(sliceQuad(quad, -0.5, 1.5), quad);
    });
  });

  group('charBoxesFromSpans', () {
    test('one box per span, in order, with its character', () {
      final boxes = charBoxesFromSpans(quad, const [
        CharSpan('Α', 0, 0.5),
        CharSpan('β', 0.5, 1),
      ]);

      expect(boxes.map((b) => b.character), ['Α', 'β']);
      expect(boxes[0].quad[1].x, closeTo(0.4, 1e-9));
      expect(boxes[1].quad[0].x, closeTo(0.4, 1e-9));
      expect(boxes[1].quad[1].x, closeTo(0.6, 1e-9));
    });

    test('no spans: no boxes', () {
      expect(charBoxesFromSpans(quad, const []), isEmpty);
    });
  });
}
