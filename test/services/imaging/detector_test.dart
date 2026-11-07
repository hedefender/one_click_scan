import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/imaging/quad.dart';
import 'package:one_click_scan/services/imaging/confidence.dart';
import 'package:one_click_scan/services/imaging/detection.dart';
import 'package:one_click_scan/services/imaging/gray.dart';
import 'package:one_click_scan/services/imaging/polygon.dart';
import 'package:one_click_scan/services/imaging/pure_dart_detector.dart';

import '../../support/synth/quad_metrics.dart';
import '../../support/synth/scene.dart';

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

RgbFrame frameOf(SceneResult r) {
  final rgb = r.image.getBytes();
  return RgbFrame(r.image.width, r.image.height, rgb);
}

bool inside(Quad q, Pt p, {double slack = 1e-6}) {
  var sign = 0;
  for (var i = 0; i < 4; i++) {
    final a = q.p[i], b = q.p[(i + 1) % 4];
    final c = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
    if (c.abs() < slack) continue;
    final s = c > 0 ? 1 : -1;
    if (sign == 0) sign = s;
    if (s != sign) return false;
  }
  return true;
}

void main() {
  group('hull and enclosing quad', () {
    test('hull drops interior points', () {
      final pts = [
        const Pt(0, 0),
        const Pt(10, 0),
        const Pt(10, 10),
        const Pt(0, 10),
        const Pt(5, 5),
        const Pt(3, 7),
        const Pt(5, 0),
      ];
      expect(convexHull(pts).length, 4);
    });

    test('a rectangle with cut corners is enclosed by a quad', () {
      // An octagon: a 100 x 60 rectangle with the corners cut by 8.
      final octagon = [
        const Pt(8, 0),
        const Pt(92, 0),
        const Pt(100, 8),
        const Pt(100, 52),
        const Pt(92, 60),
        const Pt(8, 60),
        const Pt(0, 52),
        const Pt(0, 8),
      ];
      final q = enclosingQuad(convexHull(octagon))!;
      for (final p in octagon) {
        expect(inside(q, p, slack: 1e-6) || _near(q, p), isTrue, reason: '$p');
      }
      expect(
        q.area,
        greaterThanOrEqualTo(polygonArea(convexHull(octagon)) - 1e-6),
      );
      expect(q.area, lessThan(100 * 60 * 1.05));
    });

    test('four points give that quad, a triangle gives none', () {
      final four = enclosingQuad([
        const Pt(0, 0),
        const Pt(10, 0),
        const Pt(10, 10),
        const Pt(0, 10),
      ])!;
      expect(four.area, closeTo(100, 1e-9));
      expect(
        enclosingQuad([const Pt(0, 0), const Pt(10, 0), const Pt(5, 9)]),
        isNull,
      );
    });
  });

  group('grey and Otsu', () {
    test('downscale keeps the aspect ratio and averages', () {
      final rgb = Uint8List(100 * 50 * 3)..fillRange(0, 100 * 50 * 3, 200);
      final g = grayDownscaled(RgbFrame(100, 50, rgb), maxSide: 50);
      expect(g.width, 50);
      expect(g.height, 25);
      expect(g.scale, 2);
      expect(g.data.every((v) => v == 200), isTrue);
    });

    test('otsu splits two grey levels', () {
      final data = Uint8List(1000);
      for (var i = 0; i < 1000; i++) {
        data[i] = i < 400 ? 40 : 210;
      }
      final t = otsuThreshold(data);
      expect(t, inInclusiveRange(40, 209));
      final upper = Uint8List.fromList([
        for (var i = 0; i < 900; i++) i < 300 ? 100 : (i < 600 ? 160 : 230),
      ]);
      expect(otsuThreshold(upper, above: 100), inInclusiveRange(160, 229));
    });
  });

  group('detector A3 on rendered scenes', () {
    final page = plainPage();

    test('finds a tilted page on a table, tightly', () {
      const spec = SceneSpec(
        id: 't',
        category: 't',
        document: 'x',
        seed: 5,
        width: 600,
        height: 800,
        tiltXDeg: 12,
        rollDeg: 6,
        fill: 0.8,
      );
      final r = renderScene(spec, page);
      final d = const PureDartDetector().detect(frameOf(r));
      expect(d.quad, isNotNull);
      final iou = quadIou(d.quad!, r.truth!);
      expect(iou, greaterThan(0.93));
      expect(d.confidence.value, greaterThan(0.6));
    });

    test('a page on a dark background', () {
      const spec = SceneSpec(
        id: 't',
        category: 't',
        document: 'x',
        seed: 6,
        width: 600,
        height: 800,
        background: Background.dark,
        fill: 0.75,
      );
      final r = renderScene(spec, page);
      final d = const PureDartDetector().detect(frameOf(r));
      expect(quadIou(d.quad!, r.truth!), greaterThan(0.93));
    });

    test('a background of lines and no page is not trusted', () {
      const spec = SceneSpec(
        id: 't',
        category: 't',
        document: 'x',
        seed: 8,
        width: 600,
        height: 800,
        background: Background.lines,
        hasDocument: false,
      );
      final d = const PureDartDetector().detect(
        frameOf(renderScene(spec, page)),
      );
      expect(d.score, lessThan(0.3));
    });

    test('is deterministic', () {
      const spec = SceneSpec(
        id: 't',
        category: 't',
        document: 'x',
        seed: 9,
        width: 400,
        height: 560,
      );
      final f = frameOf(renderScene(spec, page));
      final a = const PureDartDetector().detect(f);
      final b = const PureDartDetector().detect(f);
      expect(a.quad!.p[0].x, b.quad!.p[0].x);
      expect(a.score, b.score);
    });
  });

  group('confidence', () {
    test('a quad that cuts the page scores lower than the page outline', () {
      final page = plainPage();
      const spec = SceneSpec(
        id: 't',
        category: 't',
        document: 'x',
        seed: 5,
        width: 600,
        height: 800,
        fill: 0.8,
        noise: 0,
      );
      final r = renderScene(spec, page);
      final frame = frameOf(r);
      final gray = grayDownscaled(frame, maxSide: 800);
      final blur = gaussianBlur5(gray);
      final grad = GradientField.of(blur, gray.width, gray.height);
      final t = r.truth!;
      final good = scoreQuad(t, gray, grad);
      // Move the right side inwards by 15% of the width: a cut through text.
      final shift = (t.p[1].x - t.p[0].x) * 0.15;
      final cut = Quad([
        t.p[0],
        Pt(t.p[1].x - shift, t.p[1].y),
        Pt(t.p[2].x - shift, t.p[2].y),
        t.p[3],
      ]);
      final bad = scoreQuad(cut, gray, grad);
      expect(good.value, greaterThan(0.8));
      expect(bad.value, lessThan(good.value));
      // One of the four sides is no longer on an edge of the picture: the
      // support drops (the other three sides keep the contrast high).
      expect(bad.support, lessThan(good.support));
    });

    test('a non-convex quad scores zero', () {
      final g = GrayImage(10, 10, Uint8List(100), 1);
      final grad = GradientField.of(g.data, 10, 10);
      final bow = Quad(const [Pt(0, 0), Pt(9, 9), Pt(9, 0), Pt(0, 9)]);
      expect(scoreQuad(bow, g, grad).value, 0);
    });
  });
}

bool _near(Quad q, Pt p) {
  // A hull vertex may sit on the quad's border within rounding.
  for (var i = 0; i < 4; i++) {
    final a = q.p[i], b = q.p[(i + 1) % 4];
    final len = a.distanceTo(b);
    final d =
        ((b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)).abs() / len;
    if (d < 1e-6) return true;
  }
  return false;
}
