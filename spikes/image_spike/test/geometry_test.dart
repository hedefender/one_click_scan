import 'package:flutter_test/flutter_test.dart';
import 'package:image_spike/src/geometry/homography.dart';
import 'package:image_spike/src/geometry/quad.dart';

Quad rect(double x0, double y0, double x1, double y1) =>
    Quad([Pt(x0, y0), Pt(x1, y0), Pt(x1, y1), Pt(x0, y1)]);

void main() {
  group('Quad', () {
    test('area, convexity and angles of a rectangle', () {
      final q = rect(0, 0, 40, 20);
      expect(q.area, closeTo(800, 1e-9));
      expect(q.isConvex, isTrue);
      for (final a in q.anglesDeg) {
        expect(a, closeTo(90, 1e-6));
      }
    });

    test('a bow tie is not convex', () {
      final q = Quad(const [Pt(0, 0), Pt(10, 10), Pt(10, 0), Pt(0, 10)]);
      expect(q.isConvex, isFalse);
    });

    test('ordered puts any permutation in TL, TR, BR, BL order', () {
      final want = rect(10, 10, 110, 60);
      final q = Quad.ordered([want.p[2], want.p[0], want.p[3], want.p[1]]);
      for (var i = 0; i < 4; i++) {
        expect(q.p[i].x, want.p[i].x);
        expect(q.p[i].y, want.p[i].y);
      }
    });

    test('ordered works for a tilted quad', () {
      final want = Quad(const [
        Pt(30, 10),
        Pt(120, 40),
        Pt(100, 130),
        Pt(10, 90),
      ]);
      final q = Quad.ordered([want.p[1], want.p[3], want.p[0], want.p[2]]);
      for (var i = 0; i < 4; i++) {
        expect(q.p[i].x, want.p[i].x);
        expect(q.p[i].y, want.p[i].y);
      }
    });

    test('json round trip', () {
      final q = rect(1.5, 2.5, 30.25, 40.75);
      final back = Quad.fromJson(q.toJson());
      for (var i = 0; i < 4; i++) {
        expect(back.p[i].x, closeTo(q.p[i].x, 0.01));
        expect(back.p[i].y, closeTo(q.p[i].y, 0.01));
      }
    });
  });

  group('IoU and coverage', () {
    test('identical quads give 1', () {
      expect(quadIou(rect(0, 0, 10, 10), rect(0, 0, 10, 10)), closeTo(1, 1e-9));
    });

    test('disjoint quads give 0', () {
      expect(quadIou(rect(0, 0, 10, 10), rect(20, 20, 30, 30)), 0);
    });

    test('half overlap gives 1/3', () {
      expect(
        quadIou(rect(0, 0, 10, 10), rect(5, 0, 15, 10)),
        closeTo(1 / 3, 1e-9),
      );
    });

    test('a quad inside another', () {
      expect(
        quadIou(rect(0, 0, 10, 10), rect(0, 0, 5, 10)),
        closeTo(0.5, 1e-9),
      );
    });

    test('coverage of truth: a crop that cuts 20% of the page', () {
      final truth = rect(0, 0, 100, 100);
      expect(coverageOfTruth(rect(0, 0, 80, 100), truth), closeTo(0.8, 1e-9));
      // A detection larger than the page cuts nothing.
      expect(coverageOfTruth(rect(-5, -5, 105, 105), truth), closeTo(1, 1e-9));
    });

    test('works for either winding order', () {
      final a = rect(0, 0, 10, 10);
      final b = Quad([a.p[0], a.p[3], a.p[2], a.p[1]]);
      expect(quadIou(a, b), closeTo(1, 1e-9));
    });
  });

  test('corner error is a share of the frame diagonal', () {
    final t = rect(0, 0, 100, 100);
    final d = rect(3, 4, 103, 104); // every corner is 5 px away
    expect(cornerErrorPct(d, t, 500), closeTo(1.0, 1e-9));
  });

  group('homography', () {
    final src = [
      const Pt(0, 0),
      const Pt(100, 0),
      const Pt(100, 200),
      const Pt(0, 200),
    ];
    final dst = [
      const Pt(12, 8),
      const Pt(180, 30),
      const Pt(160, 260),
      const Pt(5, 210),
    ];

    test('maps the source points onto the destination points', () {
      final h = homographyFromPoints(src, dst);
      for (var i = 0; i < 4; i++) {
        final m = applyHomography(h, src[i]);
        expect(m.x, closeTo(dst[i].x, 1e-6));
        expect(m.y, closeTo(dst[i].y, 1e-6));
      }
    });

    test('the inverse brings points back', () {
      final h = homographyFromPoints(src, dst);
      final p = applyHomography(h, const Pt(37, 91));
      final back = applyHomography(invert3x3(h), p);
      expect(back.x, closeTo(37, 1e-6));
      expect(back.y, closeTo(91, 1e-6));
    });

    test('collinear points are refused', () {
      final line = [
        const Pt(0, 0),
        const Pt(1, 0),
        const Pt(2, 0),
        const Pt(3, 0),
      ];
      expect(() => homographyFromPoints(line, line), throwsArgumentError);
    });
  });
}
