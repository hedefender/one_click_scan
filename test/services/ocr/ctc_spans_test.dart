import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/services/ocr/paddle/ctc_decoder.dart';

/// A `[1, T, C]` output where step `s` has probability 0.9 on class
/// `classesPerStep[s]` and the rest spread over the others.
Float32List output(List<int> classesPerStep, int classes) {
  final data = Float32List(classesPerStep.length * classes);
  for (var s = 0; s < classesPerStep.length; s++) {
    for (var c = 0; c < classes; c++) {
      data[s * classes + c] = c == classesPerStep[s]
          ? 0.9
          : 0.1 / (classes - 1);
    }
  }
  return data;
}

void main() {
  // Class 0 is the blank, then the dictionary, the last class is the space.
  const dict = ['', 'a', 'b', 'c', 'α', 'ά', ' '];

  CtcDecoded decode(List<int> steps, {int? valid}) => ctcGreedyWithSpans(
    output(steps, dict.length),
    0,
    steps.length,
    dict.length,
    valid ?? steps.length,
    dict,
  );

  group('ctcGreedyWithSpans', () {
    test('the text and the confidence are those of ctcGreedy', () {
      final steps = [0, 1, 1, 0, 2, 0, 2, 3, 3, 0];
      final flat = output(steps, dict.length);

      final plain = ctcGreedy(flat, 0, steps.length, dict.length, 10, dict);
      final withSpans = decode(steps);

      expect(withSpans.text, plain.$1);
      expect(withSpans.confidence, plain.$2);
      expect(withSpans.text, 'abbc'); // repeats merged, a blank splits "bb"
    });

    test('one span per emitted character, in order, joined = text', () {
      final decoded = decode([0, 1, 1, 0, 2, 0, 2, 3, 3, 0]);

      expect(decoded.spans.map((s) => s.character).join(), decoded.text);
      expect(decoded.spans, hasLength(4));
      for (var i = 1; i < decoded.spans.length; i++) {
        expect(
          decoded.spans[i].start,
          greaterThanOrEqualTo(decoded.spans[i - 1].start),
        );
      }
    });

    test(
      'spans follow the time steps: the centre is the middle of the run',
      () {
        // a at steps 0..1, b at 4, c at 8..9 of 10.
        final decoded = decode([1, 1, 0, 0, 2, 0, 0, 0, 3, 3]);
        final centres = [for (final s in decoded.spans) (s.start + s.end) / 2];

        // Centres of the runs: 0.1, 0.45, 0.9.
        expect(centres[0], closeTo(0.1, 0.1)); // clamped at the left end
        expect(centres[1], closeTo(0.5, 0.1));
        expect(centres[2], closeTo(0.9, 0.12));
        // The edge between two characters is the midpoint of their centres.
        expect(decoded.spans[0].end, closeTo(decoded.spans[1].start, 1e-9));
        expect(decoded.spans[1].end, closeTo(decoded.spans[2].start, 1e-9));
        expect(decoded.spans[0].start, 0.0);
        expect(decoded.spans.last.end, lessThanOrEqualTo(1.0));
      },
    );

    test('a single character covers its own run', () {
      final decoded = decode([0, 0, 1, 1, 0, 0, 0, 0]);

      expect(decoded.spans, hasLength(1));
      expect(decoded.spans.single.start, closeTo(2 / 8, 1e-9));
      expect(decoded.spans.single.end, closeTo(4 / 8, 1e-9));
    });

    test('the space is a character of its own, with a span', () {
      // a, space, b
      final decoded = decode([1, 0, 6, 0, 2, 0]);

      expect(decoded.text, 'a b');
      expect(decoded.spans.map((s) => s.character), ['a', ' ', 'b']);
    });

    test('Greek letters with and without accent stay separate characters', () {
      final decoded = decode([4, 0, 5, 0]);

      expect(decoded.text, 'αά');
      expect(decoded.spans.map((s) => s.character), ['α', 'ά']);
    });

    test('padding steps beyond [valid] are ignored, fractions use [valid]', () {
      // 10 steps in the tensor, but only the first 5 belong to the crop.
      final decoded = decode([1, 0, 2, 0, 3, 1, 1, 1, 1, 1], valid: 5);

      expect(decoded.text, 'abc');
      expect(decoded.spans.last.end, lessThanOrEqualTo(1.0));
    });

    test('nothing recognised: empty text, zero confidence, no spans', () {
      final decoded = decode([0, 0, 0, 0]);

      expect(decoded.text, '');
      expect(decoded.confidence, 0);
      expect(decoded.spans, isEmpty);
    });

    test('a class beyond the dictionary adds no character and no span', () {
      // The model has 8 classes; the dictionary only 7.
      final data = output([1, 0, 7, 0, 2, 0], 8);
      final decoded = ctcGreedyWithSpans(data, 0, 6, 8, 6, dict);

      expect(decoded.text, 'ab');
      expect(decoded.spans, hasLength(2));
    });
  });

  group('charSpans', () {
    test('no runs: no spans', () {
      expect(charSpans(const [], const [], const [], 10), isEmpty);
      expect(charSpans(const ['a'], const [0], const [0], 0), isEmpty);
    });
  });
}
