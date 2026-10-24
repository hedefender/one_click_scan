import 'dart:math' as math;
import 'dart:typed_data';

import '../ocr/spike_ocr.dart';

/// How the hidden text is cut into text runs.
enum TextMode {
  /// A: one run per OCR line, stretched to the width of the box.
  line,

  /// B: one run per word; the word's place comes from the CTC time steps.
  word,

  /// C: like B, but a word that contains a digit is one run per character.
  code,
}

extension TextModeName on TextMode {
  String get letter => switch (this) {
    TextMode.line => 'A',
    TextMode.word => 'B',
    TextMode.code => 'C',
  };
}

/// One piece of hidden text, in PDF user space (points, y up).
class TextRun {
  const TextRun({
    required this.text,
    required this.x,
    required this.y,
    required this.angle,
    required this.fontSize,
    required this.width,
  });

  final String text;

  /// Start of the baseline.
  final double x, y;

  /// Counter-clockwise, radians (PDF orientation).
  final double angle;
  final double fontSize;

  /// The width the run has to occupy on the page, in points. The writer
  /// stretches the text to it with horizontal scaling.
  final double width;
}

/// A page of the PDF: the picture and what the OCR read on it.
class PageSpec {
  PageSpec({required this.jpeg, required this.page, this.pageWidth = 595});

  /// Upright working copy (JPEG, no EXIF).
  final Uint8List jpeg;
  final SpikePage page;

  /// A4 width in points; the height follows the picture.
  final double pageWidth;

  double get scale => pageWidth / page.width;
  double get pageHeight => page.height * scale;
}

/// Share of the box height that lies below the baseline (descenders and the
/// margin the detector adds).
const _baselineFromBottom = 0.22;

/// Font size as a share of the box height.
const _fontShare = 0.72;

/// The runs of [spec] for [mode].
List<TextRun> layoutRuns(PageSpec spec, TextMode mode) {
  final runs = <TextRun>[];
  final k = spec.scale;
  for (final line in spec.page.lines) {
    final box = line.box;
    final cs = math.cos(box.angle), sn = math.sin(box.angle);
    final vBase = box.h / 2 - _baselineFromBottom * box.h;

    // Page-space point at distance u along the text and v below the centre.
    (double, double) at(double u, double v) {
      final px = box.cx + u * cs - v * sn;
      final py = box.cy + u * sn + v * cs;
      return (px * k, spec.pageHeight - py * k);
    }

    TextRun run(String text, double x0, double x1) {
      final (x, y) = at((x0 - 0.5) * box.w, vBase);
      return TextRun(
        text: text,
        x: x,
        y: y,
        angle: -box.angle,
        fontSize: box.h * _fontShare * k,
        width: (x1 - x0) * box.w * k,
      );
    }

    if (mode == TextMode.line || line.chars.length != line.text.length) {
      runs.add(run(line.text, 0, 1));
      continue;
    }

    // Split the characters at spaces into words.
    final words = <List<CharSpan>>[];
    var current = <CharSpan>[];
    for (final c in line.chars) {
      if (c.ch == ' ') {
        if (current.isNotEmpty) words.add(current);
        current = <CharSpan>[];
      } else {
        current.add(c);
      }
    }
    if (current.isNotEmpty) words.add(current);

    for (final word in words) {
      final text = word.map((c) => c.ch).join();
      final hasDigit = RegExp(r'[0-9]').hasMatch(text);
      if (mode == TextMode.code && hasDigit) {
        for (final c in word) {
          runs.add(run(c.ch, c.x0, c.x1));
        }
      } else {
        runs.add(run(text, word.first.x0, word.last.x1));
      }
    }
  }
  return runs;
}
