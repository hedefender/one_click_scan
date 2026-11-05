import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_spike/src/detect/detection.dart';
import 'package:image_spike/src/eval/evaluation.dart';
import 'package:image_spike/src/eval/ocr_eval.dart';
import 'package:image_spike/src/geometry/quad.dart';
import 'package:image_spike/src/image/rectify.dart';
import 'package:image_spike/src/synth/documents.dart';
import 'package:image_spike/src/synth/scene.dart';

import 'detect_test.dart' show plainPage, frameOf;

class FakeDetector implements DocumentDetector {
  FakeDetector(this.name, this.quad, this.score);

  @override
  final String name;
  final Quad? quad;
  final double score;

  @override
  Detection detect(RgbFrame frame) => Detection(
    quad: quad,
    confidence: ConfidenceParts(
      area: score,
      angle: 1,
      ratio: 1,
      support: 1,
      contrast: 1,
    ),
    candidates: quad == null ? 0 : 1,
    microsPrepare: 1000,
    microsDetect: 2000,
    microsConfidence: 500,
  );
}

RgbFrame blank(int w, int h) => RgbFrame(w, h, Uint8List(w * h * 3));

void main() {
  test('the Dart warp straightens a tilted page', () {
    const spec = SceneSpec(
      id: 't',
      category: 't',
      document: 'x',
      seed: 5,
      width: 600,
      height: 800,
      tiltYDeg: 20,
      rollDeg: 8,
      noise: 0,
      lightGradient: 0,
    );
    final r = renderScene(spec, plainPage());
    final out = warpToQuadDart(frameOf(r), r.truth!, focalPx: r.focalPx);
    // The page is 300 x 420; the first dark bar spans rows 40..52 of it.
    expect(out.width / out.height, closeTo(300 / 420, 0.03));
    int red(int x, int y) => out.rgb[(y * out.width + x) * 3];
    final x = out.width ~/ 2;
    expect(red(x, (out.height * 46 / 420).round()), lessThan(90));
    expect(red(x, (out.height * 20 / 420).round()), greaterThan(190));
    expect(red(x, (out.height * 62 / 420).round()), greaterThan(190));
  });

  group('aspect from the focal length', () {
    for (final (tx, ty, roll) in [
      (0.0, 20.0, 0.0),
      (25.0, 0.0, 0.0),
      (15.0, 30.0, 8.0),
      (-20.0, -15.0, -10.0),
      (0.0, 0.0, 12.0),
    ]) {
      test('tilt x $tx, y $ty, roll $roll recovers the page proportions', () {
        final spec = SceneSpec(
          id: 't',
          category: 't',
          document: 'x',
          seed: 1,
          width: 600,
          height: 800,
          tiltXDeg: tx,
          tiltYDeg: ty,
          rollDeg: roll,
        );
        final r = renderScene(spec, plainPage());
        final a = aspectFromFocal(r.truth!, r.focalPx, 300, 400);
        expect(a, isNotNull);
        expect(a!, closeTo(300 / 420, 300 / 420 * 0.015));
      });
    }

    test('without a focal length the sides are used', () {
      final q = Quad(const [
        Pt(100, 100),
        Pt(400, 100),
        Pt(380, 520),
        Pt(120, 520),
      ]);
      expect(aspectFromFocal(q, 0, 300, 400), isNull);
      final (w, h) = rectifiedSize(q, cx: 300, cy: 400);
      expect(w, 280);
      expect(h, 420);
    });
  });

  test('rectified size keeps the proportions and respects the cap', () {
    final q = Quad(const [Pt(0, 0), Pt(300, 0), Pt(300, 600), Pt(0, 600)]);
    expect(rectifiedSize(q), (300, 600));
    expect(rectifiedSize(q, maxSide: 300), (150, 300));
  });

  group('OCR gain logic with a fake engine', () {
    final doc = documentByName('receipt_en');
    final truth = Quad(const [Pt(20, 20), Pt(80, 20), Pt(80, 90), Pt(20, 90)]);

    EvalImage image(String id, {bool partial = false}) => EvalImage(
      id: id,
      category: 'frontal',
      frame: blank(100, 100),
      truth: truth,
      partial: partial,
      fillsFrame: false,
      document: doc.name,
    );

    // Whole frame: half the lines. Any crop: every line.
    Future<OcrRun> fakeOcr(RgbFrame f, String pack) async {
      final isFrame = f.width == 100 && f.height == 100;
      final lines = isFrame
          ? doc.lines.take(doc.lines.length ~/ 2).toList()
          : doc.lines;
      return OcrRun(lines: lines, wallMs: isFrame ? 100 : 80);
    }

    RgbFrame fakeWarp(RgbFrame f, Quad q, double focalPx) => blank(60, 70);

    test(
      'rows for frame, oracle and pipelines; identical crops share the OCR',
      () async {
        var calls = 0;
        final rows = await evaluateOcrGain(
          images: [image('a')],
          pipelines: [
            Pipeline('P1', FakeDetector('d1', truth, 0.9), fakeWarp),
            Pipeline('P2', FakeDetector('d2', truth, 0.9), fakeWarp),
            Pipeline('P3', FakeDetector('d3', truth, 0.2), fakeWarp),
          ],
          oracleWarp: fakeWarp,
          ocr: (f, p) {
            calls++;
            return fakeOcr(f, p);
          },
        );
        expect(rows.map((r) => r.condition), [
          'frame',
          'oracle',
          'P1',
          'P2',
          'P3',
        ]);
        // frame, oracle and P1 are read; P2 reuses P1; P3 is not trusted.
        expect(calls, 3);
        final p2 = rows[3];
        expect(p2.reusedFrom, 'P1');
        expect(p2.used, isTrue);
        final p3 = rows[4];
        expect(p3.used, isFalse);
        expect(p3.cer, rows[0].cer);
        // The crop reads everything, the frame half.
        expect(rows[2].cer, 0);
        expect(rows[0].cer, greaterThan(0.3));
        expect(rows[2].wordRecall, 1);
        expect(rows[2].detectMs, closeTo(3.5, 1e-9));
      },
    );

    test(
      'no oracle for a page that leaves the frame; no OCR without a page',
      () async {
        final noDoc = EvalImage(
          id: 'n',
          category: 'no_document',
          frame: blank(100, 100),
          truth: null,
          partial: false,
          fillsFrame: false,
        );
        final rows = await evaluateOcrGain(
          images: [image('p', partial: true), noDoc],
          pipelines: const [],
          oracleWarp: fakeWarp,
          ocr: fakeOcr,
        );
        expect(rows.map((r) => r.condition), ['frame']);
      },
    );

    test('the safety check keeps a crop that reads as much, drops one that reads less', () {
      OcrRow row(String cond, int words, {bool used = true}) => OcrRow(
        id: 'a',
        category: 'c',
        condition: cond,
        used: used,
        cer: 0.1,
        wordRecall: 0.9,
        keyRecall: 1,
        order: 1,
        orderMatched: 5,
        ocrWords: words,
        ocrMs: 100,
      );
      final frame = row('frame', 100, used: false);
      expect(applySafetyCheck(frame, row('P', 95)).condition, 'P');
      expect(applySafetyCheck(frame, row('P', 89)).condition, 'P+check');
      expect(applySafetyCheck(frame, row('P', 89)).used, isFalse);
      // Not cropped: nothing to check.
      expect(applySafetyCheck(frame, row('P', 10, used: false)).condition, 'P');
    });

    test(
      'frame-text coverage is the share of the frame words read in the crop',
      () async {
        // The frame reads the first half of the lines; this crop reads only the
        // first quarter, so half of the frame's words are missing from it.
        Future<OcrRun> quarterCrop(RgbFrame f, String pack) async {
          final isFrame = f.width == 100 && f.height == 100;
          final n = isFrame ? doc.lines.length ~/ 2 : doc.lines.length ~/ 4;
          return OcrRun(lines: doc.lines.take(n).toList(), wallMs: 10);
        }

        final rows = await evaluateOcrGain(
          images: [image('a')],
          pipelines: [Pipeline('P1', FakeDetector('d1', truth, 0.9), fakeWarp)],
          oracleWarp: fakeWarp,
          ocr: quarterCrop,
        );
        final frame = rows.firstWhere((r) => r.condition == 'frame');
        final p1 = rows.firstWhere((r) => r.condition == 'P1');
        expect(frame.frameCoverage, 1);
        expect(p1.frameCoverage, lessThan(0.7));
        expect(p1.frameCoverage, greaterThan(0.3));
      },
    );

    test('the report names the sections', () async {
      final rows = await evaluateOcrGain(
        images: [image('a'), image('b')],
        pipelines: [Pipeline('P1', FakeDetector('d1', truth, 0.9), fakeWarp)],
        oracleWarp: fakeWarp,
        ocr: fakeOcr,
      );
      final report = formatOcrReport(rows);
      expect(report, contains('Paired change against the whole frame'));
      expect(report, contains('Safety check after the crop'));
      expect(report, contains('| P1 |'));
      expect(report, contains('| oracle |'));
    });
  });
}
