import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/services/ocr/paddle/ctc_decoder.dart';
import 'package:one_click_scan/services/ocr/paddle/detection_postprocess.dart';
import 'package:one_click_scan/services/ocr/paddle/detection_preprocess.dart';
import 'package:one_click_scan/services/ocr/paddle/paddle_constants.dart';
import 'package:one_click_scan/services/ocr/paddle/pixels.dart';
import 'package:one_click_scan/services/ocr/paddle/recognition_preprocess.dart';
import 'package:one_click_scan/services/ocr/paddle/text_box.dart';

/// RGB pixels of one flat colour.
Pixels flat(int w, int h, int r, int g, int b) {
  final data = Uint8List(w * h * 3);
  for (var i = 0; i < w * h; i++) {
    data[3 * i] = r;
    data[3 * i + 1] = g;
    data[3 * i + 2] = b;
  }
  return Pixels(data, w, h, 3);
}

/// Probability map with filled rectangles of [value].
Float32List mapWith(
  int w,
  int h,
  List<(int, int, int, int)> rects, [
  double value = 0.9,
]) {
  final prob = Float32List(w * h);
  for (final (x0, y0, x1, y1) in rects) {
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        prob[y * w + x] = value;
      }
    }
  }
  return prob;
}

void main() {
  group('detDims (detection input size, 960 side, multiples of 32)', () {
    test('a large portrait page is limited to 960 on the long side', () {
      final (w, h) = detDims(1920, 2560, 960);

      expect((w, h), (736, 960));
      expect(w % 32, 0);
      expect(h % 32, 0);
    });

    test('a landscape page', () {
      expect(detDims(2560, 1920, 960), (960, 736));
    });

    test('small images are not enlarged, only rounded to 32', () {
      expect(detDims(100, 50, 960), (96, 64));
    });

    test('never below one multiple of 32', () {
      expect(detDims(5, 5, 960), (32, 32));
    });
  });

  group('detectionInput (normalisation and tensor layout)', () {
    test('layout is [B plane, G plane, R plane] of dh x dw', () {
      final input = detectionInput(flat(64, 64, 255, 0, 0), 32, 32);

      expect(input.length, 3 * 32 * 32);
      const mean = PaddleConstants.detMean, std = PaddleConstants.detStd;
      // Pure red: B = 0, G = 0, R = 255.
      expect(input[0], closeTo((0 - mean[0]) / std[0], 1e-4));
      expect(input[32 * 32], closeTo((0 - mean[1]) / std[1], 1e-4));
      expect(input[2 * 32 * 32], closeTo((1 - mean[2]) / std[2], 1e-4));
    });

    test('white maps to (1 - mean) / std in every plane', () {
      final input = detectionInput(flat(32, 32, 255, 255, 255), 32, 32);

      const mean = PaddleConstants.detMean, std = PaddleConstants.detStd;
      for (var c = 0; c < 3; c++) {
        expect(input[c * 1024 + 500], closeTo((1 - mean[c]) / std[c], 1e-4));
      }
    });

    test('RGBA input (stride 4) gives the same tensor as RGB', () {
      final rgb = flat(40, 30, 10, 120, 240);
      final rgba = Uint8List(40 * 30 * 4);
      for (var i = 0; i < 40 * 30; i++) {
        rgba[4 * i] = 10;
        rgba[4 * i + 1] = 120;
        rgba[4 * i + 2] = 240;
        rgba[4 * i + 3] = 255;
      }

      final a = detectionInput(rgb, 32, 32);
      final b = detectionInput(Pixels(rgba, 40, 30, 4), 32, 32);

      expect(b, a);
    });

    test('resizing a left/right split keeps the split', () {
      final data = Uint8List(64 * 64 * 3);
      for (var y = 0; y < 64; y++) {
        for (var x = 32; x < 64; x++) {
          data[(y * 64 + x) * 3] = 255;
        }
      }

      final input = detectionInput(Pixels(data, 64, 64, 3), 32, 32);
      final rPlane = 2 * 1024;

      expect(input[rPlane + 5 * 32 + 2], lessThan(input[rPlane + 5 * 32 + 29]));
    });
  });

  group('boxesFromMap (DB post-processing)', () {
    test('one text region becomes one box around it, grown by unclip', () {
      final prob = mapWith(100, 60, [(20, 20, 80, 30)]);

      final boxes = boxesFromMap(prob, 100, 60, 1, 1);

      expect(boxes, hasLength(1));
      final b = boxes.single;
      expect(b.cx, closeTo(50, 1));
      expect(b.cy, closeTo(25, 1));
      expect(b.w, greaterThan(60)); // 60 wide region, unclipped
      expect(b.h, greaterThan(10));
      expect(b.angle.abs(), lessThan(0.05));
    });

    test('below the detection threshold nothing is found', () {
      final prob = mapWith(100, 60, [(20, 20, 80, 30)], 0.2);

      expect(boxesFromMap(prob, 100, 60, 1, 1), isEmpty);
    });

    test('a region whose mean probability is below 0.6 is dropped', () {
      final prob = mapWith(100, 60, [(20, 20, 80, 30)], 0.5);

      expect(boxesFromMap(prob, 100, 60, 1, 1), isEmpty);
    });

    test('tiny specks are noise', () {
      final prob = mapWith(100, 60, [(10, 10, 13, 13)]);

      expect(boxesFromMap(prob, 100, 60, 1, 1), isEmpty);
    });

    test('boxes are scaled to the image by toX and toY', () {
      final prob = mapWith(100, 60, [(20, 20, 80, 30)]);

      final small = boxesFromMap(prob, 100, 60, 1, 1).single;
      final big = boxesFromMap(prob, 100, 60, 4, 4).single;

      expect(big.cx, closeTo(small.cx * 4, 1e-6));
      expect(big.w, closeTo(small.w * 4, 1e-6));
    });

    test('touching rows are separate regions, listed top to bottom', () {
      final prob = mapWith(120, 80, [(10, 50, 100, 60), (10, 10, 100, 20)]);

      final boxes = boxesFromMap(prob, 120, 80, 1, 1);

      expect(boxes, hasLength(2));
      expect(boxes[0].cy, lessThan(boxes[1].cy));
      expect(boxes.map((b) => b.row), [0, 1]);
    });

    test('two segments of one line share a row and read left to right', () {
      final prob = mapWith(200, 60, [(100, 20, 180, 30), (10, 20, 80, 30)]);

      final boxes = boxesFromMap(prob, 200, 60, 1, 1);

      expect(boxes, hasLength(2));
      expect(boxes[0].cx, lessThan(boxes[1].cx));
      expect(boxes.map((b) => b.row), [0, 0]);
    });

    test('a tilted line gets a tilted box', () {
      // A band rising to the right by about 10 degrees.
      final prob = Float32List(200 * 100);
      for (var x = 20; x < 180; x++) {
        final yc = 60 - ((x - 20) * math.tan(10 * math.pi / 180)).round();
        for (var dy = -4; dy <= 4; dy++) {
          prob[(yc + dy) * 200 + x] = 0.9;
        }
      }

      final box = boxesFromMap(prob, 200, 100, 1, 1).single;

      // Rising to the right is a negative angle (y grows downwards).
      expect(box.angle, closeTo(-10 * math.pi / 180, 0.05));
    });

    test('an empty map has no boxes', () {
      expect(boxesFromMap(Float32List(64 * 64), 64, 64, 1, 1), isEmpty);
    });
  });

  group('sortBoxes (reading order)', () {
    test('rows by height, then left to right', () {
      final boxes = [
        TextBox(150, 100, 40, 12, 0),
        TextBox(50, 20, 40, 12, 0),
        TextBox(50, 100, 40, 12, 0),
        TextBox(150, 22, 40, 12, 0),
      ];

      final sorted = sortBoxes(boxes);

      expect(sorted.map((b) => (b.cx.round(), b.cy.round())), [
        (50, 20),
        (150, 22),
        (50, 100),
        (150, 100),
      ]);
      expect(sorted.map((b) => b.row), [0, 0, 1, 1]);
    });
  });

  group('TextBox geometry', () {
    test('quad of an axis-aligned box is normalised and clockwise from the '
        'top-left', () {
      final box = TextBox(500, 100, 200, 20, 0);

      final q = box.quad(1000, 400);

      expect(q[0].x, closeTo(0.4, 1e-9)); // top-left
      expect(q[0].y, closeTo(0.225, 1e-9));
      expect(q[1].x, closeTo(0.6, 1e-9)); // top-right
      expect(q[2].y, closeTo(0.275, 1e-9)); // bottom-right
      expect(q[3].x, closeTo(0.4, 1e-9)); // bottom-left
    });

    test(
      'quad of a tilted box is a rotated rectangle, not its bounding box',
      () {
        final box = TextBox(500, 200, 200, 20, math.pi / 12);

        final q = box.quad(1000, 400);

        // Top edge is not horizontal.
        expect(q[1].y, isNot(closeTo(q[0].y, 1e-3)));
        // Opposite corners mirror around the centre.
        expect((q[0].x + q[2].x) / 2, closeTo(0.5, 1e-9));
        expect((q[0].y + q[2].y) / 2, closeTo(0.5, 1e-9));
      },
    );

    test('coordinates are clamped to 0..1', () {
      final q = TextBox(5, 5, 400, 40, 0).quad(100, 100);

      for (final p in q) {
        expect(p.x, inInclusiveRange(0.0, 1.0));
        expect(p.y, inInclusiveRange(0.0, 1.0));
      }
    });

    test('crop width follows the aspect ratio between 16 and 2048', () {
      expect(TextBox(0, 0, 480, 48, 0).cropWidth, 480);
      expect(TextBox(0, 0, 10, 100, 0).cropWidth, 16);
      expect(TextBox(0, 0, 100000, 10, 0).cropWidth, 2048);
    });
  });

  group('cropInto (recognition input)', () {
    test('a flat grey patch is normalised to (v / 255 - 0.5) / 0.5', () {
      final p = flat(100, 100, 127, 127, 127);
      final box = TextBox(50, 50, 40, 10, 0);
      final w = box.cropWidth;
      final out = Float32List(3 * PaddleConstants.recHeight * w);

      cropInto(p, box, out, 0, w);

      expect(out[0], closeTo(127 / 127.5 - 1, 1e-5));
      expect(out.last, closeTo(127 / 127.5 - 1, 1e-5));
    });

    test('white is +1, black is -1', () {
      final box = TextBox(20, 20, 20, 8, 0);
      final w = box.cropWidth;
      final out = Float32List(3 * PaddleConstants.recHeight * w);

      cropInto(flat(40, 40, 255, 255, 255), box, out, 0, w);
      expect(out[10], closeTo(1.0, 1e-6));
      cropInto(flat(40, 40, 0, 0, 0), box, out, 0, w);
      expect(out[10], closeTo(-1.0, 1e-6));
    });

    test('a wider batch plane leaves the padding at zero', () {
      final box = TextBox(20, 20, 20, 8, 0);
      final w = box.cropWidth;
      const planeW = 200;
      final out = Float32List(3 * PaddleConstants.recHeight * planeW);

      cropInto(flat(40, 40, 255, 255, 255), box, out, 0, planeW);

      expect(out[w - 1], closeTo(1.0, 1e-6));
      expect(out[w], 0.0);
    });

    test('planes are written B, G, R', () {
      final box = TextBox(20, 20, 20, 8, 0);
      final w = box.cropWidth;
      final out = Float32List(3 * PaddleConstants.recHeight * w);

      cropInto(flat(40, 40, 255, 0, 0), box, out, 0, w); // pure red

      final plane = PaddleConstants.recHeight * w;
      expect(out[0], closeTo(-1.0, 1e-6)); // B
      expect(out[plane], closeTo(-1.0, 1e-6)); // G
      expect(out[2 * plane], closeTo(1.0, 1e-6)); // R
    });
  });

  group('CTC greedy decode', () {
    // dictionary: blank, a, b, c, space-at-end
    final dict = parseDictionary('a\nb\nc\n');

    /// One-hot probabilities for a class sequence: [steps] x [classes].
    Float32List seq(List<int> classesPerStep, int classes, [double p = 0.9]) {
      final data = Float32List(classesPerStep.length * classes);
      for (var s = 0; s < classesPerStep.length; s++) {
        for (var c = 0; c < classes; c++) {
          data[s * classes + c] = c == classesPerStep[s] ? p : 0.01;
        }
      }
      return data;
    }

    test('the table has the blank first and the space last', () {
      expect(dict, ['', 'a', 'b', 'c', ' ']);
    });

    test('repeats merge and blanks separate real repeats', () {
      // a a _ a b b _ c  ->  "aabc" (a,a merge; blank; a again; b,b merge)
      final data = seq([1, 1, 0, 1, 2, 2, 0, 3], 5);

      final (text, conf) = ctcGreedy(data, 0, 8, 5, 8, dict);

      expect(text, 'aabc');
      expect(conf, closeTo(0.9, 1e-6));
    });

    test('only blanks give empty text and zero confidence', () {
      final (text, conf) = ctcGreedy(seq([0, 0, 0], 5), 0, 3, 5, 3, dict);

      expect(text, '');
      expect(conf, 0.0);
    });

    test('the space class is decoded as a space', () {
      final (text, _) = ctcGreedy(seq([1, 0, 4, 0, 2], 5), 0, 5, 5, 5, dict);

      expect(text, 'a b');
    });

    test('only the first `steps` steps are used (batch padding)', () {
      final data = seq([1, 2, 3, 3, 3], 5);

      final (text, _) = ctcGreedy(data, 0, 5, 5, 2, dict);

      expect(text, 'ab');
    });

    test('item selects its slice of a batch', () {
      final a = seq([1, 1], 5), b = seq([3, 3], 5);
      final both = Float32List.fromList([...a, ...b]);

      expect(ctcGreedy(both, 0, 2, 5, 2, dict).$1, 'a');
      expect(ctcGreedy(both, 1, 2, 5, 2, dict).$1, 'c');
    });

    test('the confidence is the mean over emitted characters only', () {
      final data = Float32List(3 * 5);
      void set(int s, int c, double p) => data[s * 5 + c] = p;
      set(0, 1, 0.8);
      set(1, 0, 0.99);
      set(2, 2, 0.6);

      final (text, conf) = ctcGreedy(data, 0, 3, 5, 3, dict);

      expect(text, 'ab');
      expect(conf, closeTo(0.7, 1e-6));
    });

    test('a class beyond the dictionary is skipped, not a crash', () {
      final (text, _) = ctcGreedy(seq([1, 6], 8), 0, 2, 8, 2, dict);

      expect(text, 'a');
    });

    test('dictionary parsing handles CRLF and a trailing newline', () {
      expect(parseDictionary('x\r\ny\r\n'), ['', 'x', 'y', ' ']);
    });
  });
}
