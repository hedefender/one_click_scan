import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/ocr_line.dart';
import 'package:one_click_scan/domain/ocr/char_boxes.dart';
import 'package:one_click_scan/domain/pdf/pdf_config.dart';
import 'package:one_click_scan/domain/pdf/pdf_text_layout.dart';

/// Working image used by the tests: 1000 x 2000 px, so a page of 360 x 720 pt
/// (72 / 200 points per pixel).
const imageWidth = 1000;
const imageHeight = 2000;
const k = PdfConfig.pointsPerInch / PdfConfig.dpi;

List<OcrPoint> rect(double x0, double y0, double x1, double y1) => [
  OcrPoint(x0, y0),
  OcrPoint(x1, y0),
  OcrPoint(x1, y1),
  OcrPoint(x0, y1),
];

/// A line whose characters share the box equally.
OcrLine lineOf(
  String text,
  List<OcrPoint> quad, {
  bool withBoxes = true,
  double confidence = 0.95,
  bool filtered = false,
}) {
  final characters = text.split('');
  final n = characters.length;
  return OcrLine(
    text: text,
    confidence: confidence,
    quad: quad,
    filtered: filtered,
    charBoxes: withBoxes
        ? charBoxesFromSpans(quad, [
            for (var i = 0; i < n; i++)
              CharSpan(characters[i], i / n, (i + 1) / n),
          ])
        : null,
  );
}

List<PdfTextRun> layout(List<OcrLine> lines) => layoutPageText(
  lines: lines,
  imageWidth: imageWidth,
  imageHeight: imageHeight,
);

void main() {
  test('the page keeps the ratio of the picture, at 200 dpi', () {
    final size = pageSizeFor(imageWidth, imageHeight);

    expect(size.width, closeTo(360, 1e-9));
    expect(size.height, closeTo(720, 1e-9));
    expect(size.height / size.width, closeTo(imageHeight / imageWidth, 1e-9));
  });

  test('a 2560 x 1920 working copy is about 12.8 x 9.6 in', () {
    final size = pageSizeFor(2560, 1920);

    expect(size.width / 72, closeTo(12.8, 1e-9));
    expect(size.height / 72, closeTo(9.6, 1e-9));
  });

  group('position of a horizontal line (one word)', () {
    // Box: x 100..500 px, y 200..300 px.
    final quad = rect(0.1, 0.1, 0.5, 0.15);

    test('baseline start, font size and width in PDF points', () {
      final runs = layout([lineOf('Total', quad, withBoxes: false)]);

      expect(runs, hasLength(1));
      final run = runs.single;
      expect(run.text, 'Total');
      // x: 100 px; y: 200 + 0.78 * 100 = 278 px from the top.
      expect(run.x, closeTo(100 * k, 1e-9));
      // y axis flipped: page height 720 pt.
      expect(run.y, closeTo(720 - 278 * k, 1e-9));
      expect(run.angle, closeTo(0, 1e-12));
      expect(run.fontSize, closeTo(100 * 0.72 * k, 1e-9));
      expect(run.width, closeTo(400 * k, 1e-9));
    });

    test('the baseline is inside the box, near its bottom', () {
      final run = layout([lineOf('Total', quad, withBoxes: false)]).single;
      final top = 720 - 200 * k;
      final bottom = 720 - 300 * k;

      expect(run.y, lessThan(top));
      expect(run.y, greaterThan(bottom));
      expect(run.y - bottom, closeTo(0.22 * 100 * k, 1e-9));
    });

    test('a box lower on the page gets a lower y (y is flipped)', () {
      final upper = layout([lineOf('a', rect(0.1, 0.1, 0.3, 0.15))]).single;
      final lower = layout([lineOf('a', rect(0.1, 0.6, 0.3, 0.65))]).single;

      expect(lower.y, lessThan(upper.y));
    });

    test('scale: the run width is the width of the box on the page', () {
      final wide = layout([lineOf('a', rect(0.1, 0.1, 0.9, 0.15))]).single;
      final narrow = layout([lineOf('a', rect(0.1, 0.1, 0.3, 0.15))]).single;

      expect(wide.width / narrow.width, closeTo(4, 1e-9));
    });
  });

  group('tilt', () {
    /// A box of [w] x [h] px whose top-left corner is at ([x], [y]) px,
    /// rotated by [degrees] clockwise (image y points down) around that corner.
    List<OcrPoint> tilted(
      double x,
      double y,
      double w,
      double h,
      double degrees,
    ) {
      final a = degrees * math.pi / 180;
      final c = math.cos(a), s = math.sin(a);
      OcrPoint at(double u, double v) => OcrPoint(
        (x + u * c - v * s) / imageWidth,
        (y + u * s + v * c) / imageHeight,
      );
      return [at(0, 0), at(w, 0), at(w, h), at(0, h)];
    }

    test('text going down to the right has a negative PDF angle', () {
      final run = layout([lineOf('x', tilted(200, 400, 300, 60, 10))]).single;

      expect(run.angle, closeTo(-10 * math.pi / 180, 1e-9));
    });

    test('text rising to the right has a positive PDF angle', () {
      final run = layout([lineOf('x', tilted(200, 800, 300, 60, -7))]).single;

      expect(run.angle, closeTo(7 * math.pi / 180, 1e-9));
    });

    test('tilting does not change the size or the width', () {
      final flat = layout([lineOf('x', tilted(200, 400, 300, 60, 0))]).single;
      final slanted = layout([lineOf('x', tilted(200, 400, 300, 60, 15))])
          .single;

      expect(slanted.width, closeTo(flat.width, 1e-6));
      expect(slanted.fontSize, closeTo(flat.fontSize, 1e-6));
    });

    test('the baseline of a tilted box stays on the box (the start moves '
        'along its down direction)', () {
      final run = layout([lineOf('x', tilted(200, 400, 300, 100, 20))]).single;
      final a = 20 * math.pi / 180;
      // Start: corner + 0.78 * h along the down direction (-sin, cos).
      final px = 200 - 0.78 * 100 * math.sin(a);
      final py = 400 + 0.78 * 100 * math.cos(a);

      expect(run.x, closeTo(px * k, 1e-6));
      expect(run.y, closeTo(720 - py * k, 1e-6));
    });
  });

  group('one run per word (from the character boxes)', () {
    final quad = rect(0.1, 0.1, 0.5, 0.15); // 400 px wide

    test('Latin words and digits', () {
      final runs = layout([lineOf('Total 12,50 EUR', quad)]);

      expect(runs.map((r) => r.text), ['Total', '12,50', 'EUR']);
    });

    test('Greek words with accents', () {
      final runs = layout([lineOf('Σύνολο πληρωμής', quad)]);

      expect(runs.map((r) => r.text), ['Σύνολο', 'πληρωμής']);
    });

    test('mixed Greek and Latin in one line', () {
      final runs = layout([lineOf('ΑΦΜ VAT 123456789', quad)]);

      expect(runs.map((r) => r.text), ['ΑΦΜ', 'VAT', '123456789']);
    });

    test('each word sits where its own characters are', () {
      // "ab cd": five equal characters of 80 px: a 100-180, b 180-260,
      // space 260-340, c 340-420, d 420-500.
      final runs = layout([lineOf('ab cd', quad)]);

      expect(runs, hasLength(2));
      expect(runs[0].x, closeTo(100 * k, 1e-9));
      expect(runs[0].width, closeTo(160 * k, 1e-9));
      expect(runs[1].x, closeTo(340 * k, 1e-9));
      expect(runs[1].width, closeTo(160 * k, 1e-9));
      // Same baseline and size for the whole line.
      expect(runs[1].y, closeTo(runs[0].y, 1e-9));
      expect(runs[1].fontSize, closeTo(runs[0].fontSize, 1e-9));
    });

    test('the words of a line end where the line ends', () {
      final runs = layout([lineOf('ab cd', quad)]);

      expect(runs.last.x + runs.last.width, closeTo(500 * k, 1e-9));
    });

    test('spaces at the ends and repeated spaces give no empty word', () {
      final runs = layout([lineOf('  ab   cd  ', quad)]);

      expect(runs.map((r) => r.text), ['ab', 'cd']);
    });

    test('a line that is only spaces gives nothing', () {
      expect(layout([lineOf('    ', quad)]), isEmpty);
    });

    test('an empty line gives nothing', () {
      expect(layout([lineOf('', quad, withBoxes: false)]), isEmpty);
      expect(layout(const []), isEmpty);
    });

    test('a single character is a word', () {
      expect(layout([lineOf('€', quad)]).map((r) => r.text), ['€']);
    });

    test('a long code is ONE word, not split', () {
      const code = 'RF18539007547034';
      final runs = layout([lineOf(code, quad)]);

      expect(runs.map((r) => r.text), [code]);
      expect(runs.single.width, closeTo(400 * k, 1e-9));
    });

    test('the lines of a page come out in the order given', () {
      final runs = layout([
        lineOf('first line', rect(0.1, 0.1, 0.5, 0.15)),
        lineOf('second line', rect(0.1, 0.2, 0.5, 0.25)),
      ]);

      expect(runs.map((r) => r.text), ['first', 'line', 'second', 'line']);
    });
  });

  group('lines without usable character boxes', () {
    final quad = rect(0.1, 0.1, 0.5, 0.15);

    test('no charBoxes: the whole line is one run over the whole box', () {
      final runs = layout([lineOf('Total 12,50', quad, withBoxes: false)]);

      expect(runs, hasLength(1));
      expect(runs.single.text, 'Total 12,50');
      expect(runs.single.x, closeTo(100 * k, 1e-9));
      expect(runs.single.width, closeTo(400 * k, 1e-9));
    });

    test('boxes that do not add up to the text: whole line, no failure', () {
      final line = OcrLine(
        text: 'Total',
        confidence: 0.9,
        quad: quad,
        charBoxes: charBoxesFromSpans(quad, const [
          CharSpan('T', 0, 0.5),
          CharSpan('x', 0.5, 1), // not the text
        ]),
      );

      final runs = layout([line]);

      expect(runs.map((r) => r.text), ['Total']);
    });

    test('empty charBoxes list: whole line', () {
      final line = OcrLine(
        text: 'Total',
        confidence: 0.9,
        quad: quad,
        charBoxes: const [],
      );

      expect(layout([line]).map((r) => r.text), ['Total']);
    });

    test('the lines of a page can mix both kinds', () {
      final runs = layout([
        lineOf('ab cd', rect(0.1, 0.1, 0.5, 0.15)),
        lineOf('no boxes here', rect(0.1, 0.3, 0.5, 0.35), withBoxes: false),
      ]);

      expect(runs.map((r) => r.text), ['ab', 'cd', 'no boxes here']);
    });
  });

  group('which lines reach the text layer', () {
    final quad = rect(0.1, 0.1, 0.5, 0.15);

    test('filtered lines (below the confidence threshold) are skipped', () {
      final runs = layout([
        lineOf('kept', quad),
        lineOf('scribble', rect(0.1, 0.3, 0.5, 0.35), filtered: true),
      ]);

      expect(runs.map((r) => r.text), ['kept']);
    });

    test('a page of only filtered lines has no text', () {
      expect(layout([lineOf('x', quad, filtered: true)]), isEmpty);
    });

    test('a box thinner than the minimum is ignored', () {
      // 1 px high on a 2000 px page.
      final runs = layout([lineOf('hair', rect(0.1, 0.1, 0.5, 0.1005))]);

      expect(runs, isEmpty);
    });
  });
}
