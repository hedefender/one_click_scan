import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:one_click_scan/domain/entities/page_crop_outcome.dart';
import 'package:one_click_scan/domain/imaging/page_crop_config.dart';
import 'package:one_click_scan/domain/imaging/quad.dart';
import 'package:one_click_scan/services/imaging/crop_page_job.dart';
import 'package:one_click_scan/services/imaging/detection.dart';
import 'package:one_click_scan/services/imaging/pure_dart_detector.dart';

import '../../support/synth/quad_metrics.dart';
import '../../support/synth/scene.dart';

/// A flat page of 300 x 420 (an A-series ratio of 0.714) with text-like bars.
FlatPage plainPage() {
  const w = 300, h = 420;
  final rgb = Uint8List(w * h * 3)..fillRange(0, w * h * 3, 238);
  for (var row = 0; row < 12; row++) {
    for (var y = 40 + row * 28; y < 52 + row * 28; y++) {
      for (var x = 30; x < 270; x++) {
        final o = (y * w + x) * 3;
        rgb[o] = rgb[o + 1] = rgb[o + 2] = 25;
      }
    }
  }
  return FlatPage(w, h, rgb);
}

const _pageAspect = 300 / 420;

SceneSpec spec(
  String id, {
  int width = 768,
  int height = 1024,
  int seed = 7,
  double tiltXDeg = 0,
  double tiltYDeg = 0,
  double rollDeg = 0,
  double fill = 0.8,
  Background background = Background.table,
  double lightGradient = 0.12,
  bool shadowBand = false,
  double contrast = 1.0,
  double crumple = 0,
  bool hasDocument = true,
}) => SceneSpec(
  id: id,
  category: id,
  document: 'x',
  seed: seed,
  width: width,
  height: height,
  tiltXDeg: tiltXDeg,
  tiltYDeg: tiltYDeg,
  rollDeg: rollDeg,
  fill: fill,
  background: background,
  lightGradient: lightGradient,
  shadowBand: shadowBand,
  contrast: contrast,
  crumple: crumple,
  hasDocument: hasDocument,
);

/// The photo as a JPEG file, with the 35 mm focal length when [focalPx] is
/// given (what the EXIF of a phone photo has).
File writePhoto(Directory dir, SceneResult r, {bool withFocal = false}) {
  final image = r.image.clone();
  if (withFocal) {
    final diagonal = math.sqrt(
      (image.width * image.width + image.height * image.height).toDouble(),
    );
    final f35 = (r.focalPx * PageCropConfig.filmDiagonalMm / diagonal).round();
    image.exif.exifIfd.data[0xA405] = img.IfdValueShort(f35);
  }
  final file = File('${dir.path}/${r.hashCode}_${withFocal ? 'f' : 'n'}.jpg');
  file.writeAsBytesSync(img.encodeJpg(image, quality: 92));
  return file;
}

RgbFrame frameOf(SceneResult r) =>
    RgbFrame(r.image.width, r.image.height, r.image.getBytes());

void main() {
  late Directory dir;
  final page = plainPage();

  setUp(() => dir = Directory.systemTemp.createTempSync('crop_job_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  CropJob jobFor(File source, {int? focal}) => CropJob(
    source: source.path,
    target: '${dir.path}/out.jpg',
    maxSide: 2560,
    jpegQuality: 95,
    focalLength35mm: focal,
  );

  group('the threshold of confidence is one rule', () {
    test('exactly 0.5 is trusted, just below it is not', () {
      expect(PageCropConfig.minConfidence, 0.5);
      expect(trustsDetection(0.5), isTrue);
      expect(trustsDetection(0.5000001), isTrue);
      expect(trustsDetection(0.4999999), isFalse);
      expect(trustsDetection(0), isFalse);
      expect(trustsDetection(1), isTrue);
    });
  });

  group('straightening', () {
    test('a tilted page is cropped upright, in its true proportions', () {
      final r = renderScene(
        spec('tilt', tiltXDeg: 18, tiltYDeg: 10, rollDeg: 8),
        page,
      );
      final file = writePhoto(dir, r, withFocal: true);
      final f35 = img.decodeJpg(file.readAsBytesSync())!.exif.exifIfd.data;
      expect(f35[0xA405], isNotNull);

      final result = cropPageSync(jobFor(file, focal: f35[0xA405]!.toInt()));

      expect(result.reason, isNull);
      expect(result.confidence, greaterThanOrEqualTo(0.5));
      final out = img.decodeJpg(File('${dir.path}/out.jpg').readAsBytesSync())!;
      expect(out.width, result.width);
      expect(out.height, result.height);
      // With the focal length the sides keep the page's proportions.
      expect(out.width / out.height, closeTo(_pageAspect, 0.04));
    });

    test('without a focal length the page still comes out upright, a little '
        'narrow when it is tilted (the documented limit)', () {
      final r = renderScene(spec('tilt2', tiltYDeg: 20, seed: 3), page);
      final file = writePhoto(dir, r);

      final result = cropPageSync(jobFor(file));

      expect(result.reason, isNull);
      final ratio = result.width / result.height;
      // About 6% too narrow at 20 degrees (ADR-029), never wider than the page.
      expect(ratio, inInclusiveRange(_pageAspect * 0.85, _pageAspect * 1.04));
    });

    test('the crop is never larger than the working side', () {
      final r = renderScene(
        spec('big', width: 1536, height: 2048, rollDeg: 4),
        page,
      );
      final file = writePhoto(dir, r);

      final result = cropPageSync(
        CropJob(
          source: file.path,
          target: '${dir.path}/small.jpg',
          maxSide: 500,
          jpegQuality: 90,
          focalLength35mm: null,
        ),
      );

      expect(result.reason, isNull);
      expect(math.max(result.width, result.height), lessThanOrEqualTo(500));
    });

    test('the file written is a JPEG at the quality asked, at the target', () {
      final r = renderScene(spec('q', rollDeg: 5), page);
      final result = cropPageSync(jobFor(writePhoto(dir, r)));

      expect(result.reason, isNull);
      final bytes = File('${dir.path}/out.jpg').readAsBytesSync();
      expect(bytes.sublist(0, 2), [0xFF, 0xD8]);
    });
  });

  group('the whole frame, with the reason, and nothing written', () {
    void expectWholeFrame(CropJobResult result, WholeFrameReason reason) {
      expect(result.reason, reason);
      expect(result.toOutcome(), isA<PageWholeFrame>());
      expect(File('${dir.path}/out.jpg').existsSync(), isFalse);
    }

    test('an empty table: no page, or not sure', () {
      final r = renderScene(
        spec('empty', hasDocument: false, background: Background.lines),
        page,
      );

      final result = cropPageSync(jobFor(writePhoto(dir, r)));

      expect(
        result.reason,
        anyOf(WholeFrameReason.noPageFound, WholeFrameReason.lowConfidence),
      );
      expect(File('${dir.path}/out.jpg').existsSync(), isFalse);
    });

    test('a page that fills the frame has no outline to find', () {
      final r = renderScene(spec('fills', fill: 1.4), page);

      final result = cropPageSync(jobFor(writePhoto(dir, r)));

      expect(result.reason, isNotNull);
      expect(File('${dir.path}/out.jpg').existsSync(), isFalse);
    });

    test('a file that is not an image', () {
      final file = File('${dir.path}/junk.jpg')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);

      expectWholeFrame(cropPageSync(jobFor(file)), WholeFrameReason.failed);
    });

    test('a missing file', () {
      expectWholeFrame(
        cropPageSync(jobFor(File('${dir.path}/nope.jpg'))),
        WholeFrameReason.failed,
      );
    });

    test('an unwritable target is a failure, not an exception', () {
      final r = renderScene(spec('w', rollDeg: 3), page);
      final result = cropPageSync(
        CropJob(
          source: writePhoto(dir, r).path,
          target: '${dir.path}/no_such_folder/out.jpg',
          maxSide: 2560,
          jpegQuality: 95,
          focalLength35mm: null,
        ),
      );

      expect(result.reason, WholeFrameReason.failed);
    });
  });

  group('focal length in pixels', () {
    test('35 mm equivalent to pixels by the diagonal', () {
      // 3000 x 4000: diagonal 5000 px; 26 mm of a 43.27 mm diagonal.
      expect(focalPixels(26, 3000, 4000), closeTo(26 * 5000 / 43.27, 1e-6));
    });

    test('none, zero or negative mean "unknown"', () {
      expect(focalPixels(null, 3000, 4000), 0);
      expect(focalPixels(0, 3000, 4000), 0);
      expect(focalPixels(-5, 3000, 4000), 0);
    });
  });

  group('a fixed synthetic set (seeded)', () {
    // A subset of the 77 scenes of the spike: the categories that matter.
    final scenes = <SceneSpec>[
      spec('frontal_a', seed: 11, fill: 0.78),
      spec('frontal_b', seed: 12, fill: 0.82),
      spec('persp_20x', seed: 13, tiltXDeg: 20, rollDeg: 2),
      spec('persp_20y', seed: 14, tiltYDeg: -20, rollDeg: -1),
      spec('rot_10', seed: 15, rollDeg: 10, fill: 0.74),
      spec('rot_m10', seed: 16, rollDeg: -10, fill: 0.74),
      spec('light', seed: 17, lightGradient: 0.3, shadowBand: true),
      spec('low_contrast', seed: 18, contrast: 0.45, rollDeg: 3),
      spec('crumple', seed: 19, crumple: 8, tiltXDeg: 6),
      spec('dark', seed: 20, background: Background.dark, rollDeg: 5),
      spec('lines', seed: 21, background: Background.lines, fill: 0.66),
      spec('clutter', seed: 22, background: Background.clutter, rollDeg: 6),
      spec('fills_frame', seed: 23, fill: 1.4),
      spec('small', seed: 24, fill: 0.3, rollDeg: 4),
      spec(
        'none',
        seed: 25,
        hasDocument: false,
        background: Background.clutter,
      ),
    ];

    test('0 cuts of the content, 0 false crops, most pages found', () {
      const detector = PureDartDetector();
      var cuts = 0, falseCrops = 0, good = 0, cropped = 0, withPage = 0;
      for (final s in scenes) {
        final r = renderScene(s, page);
        final d = detector.detect(frameOf(r));
        final trusted = d.quad != null && trustsDetection(d.score);
        final truth = r.truth;
        if (truth == null) {
          if (trusted) falseCrops++;
          continue;
        }
        withPage++;
        if (!trusted) continue;
        cropped++;
        final coverage = coverageOfTruth(d.quad!, truth);
        // Compared with what is visible of the page: a page that leaves the
        // frame is judged inside the frame.
        final visible = r.partial || r.fillsFrame
            ? clipPolygon(truth.p, Quad.frame(r.image.width, r.image.height).p)
            : truth.p;
        final share =
            polygonArea(clipPolygon(visible, d.quad!.p)) / polygonArea(visible);
        if (share < 0.98) cuts++;
        if (quadIou(d.quad!, truth) >= 0.9 && coverage >= 0.98) good++;
      }

      expect(cuts, 0, reason: 'the PDF must never lose content');
      expect(falseCrops, 0);
      expect(cropped, greaterThanOrEqualTo(8), reason: 'of $withPage pages');
      expect(good, greaterThanOrEqualTo(cropped - 2));
    });

    test('the same input always gives the same answer', () {
      final r = renderScene(scenes[2], page);
      final a = const PureDartDetector().detect(frameOf(r));
      final b = const PureDartDetector().detect(frameOf(r));
      expect(a.score, b.score);
      expect(
        a.quad!.p.map((p) => (p.x, p.y)),
        b.quad!.p.map((p) => (p.x, p.y)),
      );
    });
  });
}
