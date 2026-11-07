import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'package:one_click_scan/domain/imaging/quad.dart';
import 'package:one_click_scan/services/imaging/homography.dart';

enum Background { table, dark, lines, clutter }

/// A flat, upright page as RGB bytes (what the renderer draws a scene from).
class FlatPage {
  FlatPage(this.width, this.height, this.rgb);

  factory FlatPage.fromImage(img.Image image) {
    final rgb = image.convert(numChannels: 3);
    return FlatPage(
      rgb.width,
      rgb.height,
      Uint8List.fromList(rgb.getBytes(order: img.ChannelOrder.rgb)),
    );
  }

  final int width;
  final int height;
  final Uint8List rgb;
}

/// Everything that decides one synthetic photo. The same spec always draws
/// the same picture (the seed drives every random choice).
class SceneSpec {
  const SceneSpec({
    required this.id,
    required this.category,
    required this.document,
    required this.seed,
    this.width = 1536,
    this.height = 2048,
    this.tiltXDeg = 0,
    this.tiltYDeg = 0,
    this.rollDeg = 0,
    this.fill = 0.8,
    this.offsetX = 0,
    this.offsetY = 0,
    this.background = Background.table,
    this.lightGradient = 0.12,
    this.shadowBand = false,
    this.contrast = 1.0,
    this.crumple = 0,
    this.hand = false,
    this.noise = 3,
    this.hasDocument = true,
  });

  final String id;
  final String category;
  final String document;
  final int seed;
  final int width;
  final int height;

  /// Rotation of the page about the horizontal and vertical axis (the
  /// perspective), and in the plane of the picture (the roll).
  final double tiltXDeg;
  final double tiltYDeg;
  final double rollDeg;

  /// Share of the frame the page's bounding box takes (the larger of the width
  /// and height shares). Above 1 the page leaves the frame.
  final double fill;
  final double offsetX;
  final double offsetY;
  final Background background;

  /// 0 is even light; 0.4 is strongly uneven.
  final double lightGradient;
  final bool shadowBand;

  /// 1 is normal; 0.4 is faint.
  final double contrast;

  /// Surface wave amplitude in page pixels (0 is flat paper).
  final double crumple;
  final bool hand;
  final double noise;
  final bool hasDocument;

  Map<String, Object> toJson() => {
    'id': id,
    'category': category,
    'document': document,
    'seed': seed,
    'width': width,
    'height': height,
    'tiltXDeg': tiltXDeg,
    'tiltYDeg': tiltYDeg,
    'rollDeg': rollDeg,
    'fill': fill,
    'offsetX': offsetX,
    'offsetY': offsetY,
    'background': background.name,
    'lightGradient': lightGradient,
    'shadowBand': shadowBand,
    'contrast': contrast,
    'crumple': crumple,
    'hand': hand,
    'noise': noise,
    'hasDocument': hasDocument,
  };
}

class SceneResult {
  SceneResult({
    required this.image,
    required this.truth,
    required this.partial,
    required this.fillsFrame,
    required this.focalPx,
  });

  final img.Image image;

  /// Focal length in frame pixels (0 when there is no document).
  final double focalPx;

  /// The true page outline in frame coordinates (may lie partly outside the
  /// frame); null when the scene has no document.
  final Quad? truth;

  /// The page leaves the frame (some of it is not in the picture).
  final bool partial;

  /// The page covers the whole frame (the right answer is the whole frame).
  final bool fillsFrame;
}

double _smoothstep(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Smooth value noise on a coarse grid, bilinear in between.
class _ValueNoise {
  _ValueNoise(math.Random rng, this.cols, this.rows)
    : _v = List.generate((cols + 1) * (rows + 1), (_) => rng.nextDouble());

  final int cols;
  final int rows;
  final List<double> _v;

  /// [u], [v] in 0..1.
  double at(double u, double v) {
    final x = u * cols, y = v * rows;
    final x0 = x.floor().clamp(0, cols - 1), y0 = y.floor().clamp(0, rows - 1);
    final fx = x - x0, fy = y - y0;
    double g(int i, int j) => _v[j * (cols + 1) + i];
    final a = g(x0, y0) * (1 - fx) + g(x0 + 1, y0) * fx;
    final b = g(x0, y0 + 1) * (1 - fx) + g(x0 + 1, y0 + 1) * fx;
    return a * (1 - fy) + b * fy;
  }
}

class _Gauss {
  _Gauss(this.rng);

  final math.Random rng;

  double next() {
    final u1 = 1 - rng.nextDouble();
    final u2 = rng.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }
}

bool _insideConvex(List<Pt> poly, double x, double y) {
  var sign = 0;
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i];
    final b = poly[(i + 1) % poly.length];
    final cross = (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x);
    if (cross.abs() < 1e-9) continue;
    final s = cross > 0 ? 1 : -1;
    if (sign == 0) sign = s;
    if (s != sign) return false;
  }
  return true;
}

/// Projects the page rectangle as a camera would see it, and fits it into the
/// frame. Returns the outline TL, TR, BR, BL in frame pixels.
Quad projectPage(SceneSpec s, int pageW, int pageH) =>
    projectPageWithFocal(s, pageW, pageH).$1;

/// Like [projectPage], and the focal length of the camera in frame pixels
/// (what the EXIF 35 mm focal length gives a real app). It changes with the
/// scene because the synthetic camera zooms to fit the page.
(Quad, double) projectPageWithFocal(SceneSpec s, int pageW, int pageH) {
  final rx = s.tiltXDeg * math.pi / 180;
  final ry = s.tiltYDeg * math.pi / 180;
  final rz = s.rollDeg * math.pi / 180;
  final dist = 2.4 * math.max(pageW, pageH);
  final corners = [
    [-pageW / 2, -pageH / 2],
    [pageW / 2, -pageH / 2],
    [pageW / 2, pageH / 2],
    [-pageW / 2, pageH / 2],
  ];
  final proj = <Pt>[];
  for (final c in corners) {
    var x = c[0], y = c[1], z = 0.0;
    // Rx
    var y1 = y * math.cos(rx) - z * math.sin(rx);
    var z1 = y * math.sin(rx) + z * math.cos(rx);
    y = y1;
    z = z1;
    // Ry
    final x2 = x * math.cos(ry) + z * math.sin(ry);
    final z2 = -x * math.sin(ry) + z * math.cos(ry);
    x = x2;
    z = z2;
    // Rz
    final x3 = x * math.cos(rz) - y * math.sin(rz);
    final y3 = x * math.sin(rz) + y * math.cos(rz);
    x = x3;
    y = y3;
    final zc = z + dist;
    proj.add(Pt(dist * x / zc, dist * y / zc));
  }
  final minX = proj.map((p) => p.x).reduce(math.min);
  final maxX = proj.map((p) => p.x).reduce(math.max);
  final minY = proj.map((p) => p.y).reduce(math.min);
  final maxY = proj.map((p) => p.y).reduce(math.max);
  final scale =
      s.fill / math.max((maxX - minX) / s.width, (maxY - minY) / s.height);
  final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
  final tx = s.width / 2 + s.offsetX * s.width;
  final ty = s.height / 2 + s.offsetY * s.height;
  return (
    Quad([
      for (final p in proj)
        Pt((p.x - cx) * scale + tx, (p.y - cy) * scale + ty),
    ]),
    dist * scale,
  );
}

Uint8List _background(SceneSpec s, math.Random rng) {
  final w = s.width, h = s.height;
  final out = Uint8List(w * h * 3);
  final coarse = _ValueNoise(rng, 6, 8);
  final fine = _ValueNoise(rng, 40, 50);
  final grainAngle = rng.nextDouble() * math.pi;
  final ca = math.cos(grainAngle), sa = math.sin(grainAngle);
  final period = 18 + rng.nextDouble() * 22;
  // Lines background: two families of straight lines.
  final lineAngle = rng.nextDouble() * math.pi;
  final l1c = math.cos(lineAngle), l1s = math.sin(lineAngle);
  final lineAngle2 = lineAngle + math.pi / 2 + (rng.nextDouble() - 0.5) * 0.5;
  final l2c = math.cos(lineAngle2), l2s = math.sin(lineAngle2);
  final linePeriod = 70 + rng.nextDouble() * 60;
  final lineWidth = 3 + rng.nextDouble() * 3;
  // Clutter: rectangles (books, papers, boxes).
  final rects = <List<double>>[];
  if (s.background == Background.clutter) {
    for (var i = 0; i < 9; i++) {
      rects.add([
        rng.nextDouble() * w,
        rng.nextDouble() * h,
        80 + rng.nextDouble() * 420,
        80 + rng.nextDouble() * 520,
        rng.nextDouble() * 0.9 - 0.45,
        60 + rng.nextDouble() * 160,
        60 + rng.nextDouble() * 160,
        60 + rng.nextDouble() * 160,
      ]);
    }
  }
  var o = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final u = x / w, v = y / h;
      double r, g, b;
      switch (s.background) {
        case Background.dark:
          final n = coarse.at(u, v) * 14 + fine.at(u, v) * 8;
          r = 22 + n;
          g = 24 + n;
          b = 28 + n;
        case Background.lines:
          final n = 0.88 + 0.12 * coarse.at(u, v);
          r = 200 * n;
          g = 200 * n;
          b = 196 * n;
          final d1 = (x * l1c + y * l1s) % linePeriod;
          final d2 = (x * l2c + y * l2s) % linePeriod;
          if (d1 < lineWidth || d2 < lineWidth) {
            r = 55;
            g = 58;
            b = 62;
          }
        case Background.table || Background.clutter:
          final wood =
              math.sin((x * ca + y * sa) / period + coarse.at(u, v) * 6) * 0.07;
          final n = 0.78 + 0.4 * coarse.at(u, v) + wood + 0.05 * fine.at(u, v);
          r = 150 * n;
          g = 108 * n;
          b = 70 * n;
          if (s.background == Background.clutter) {
            for (final q in rects) {
              final dx = x - q[0], dy = y - q[1];
              final ang = q[4];
              final rx = dx * math.cos(ang) + dy * math.sin(ang);
              final ry = -dx * math.sin(ang) + dy * math.cos(ang);
              if (rx > 0 && rx < q[2] && ry > 0 && ry < q[3]) {
                r = q[5] * n;
                g = q[6] * n;
                b = q[7] * n;
              }
            }
          }
      }
      out[o++] = r.clamp(0, 255).round();
      out[o++] = g.clamp(0, 255).round();
      out[o++] = b.clamp(0, 255).round();
    }
  }
  return out;
}

/// Draws the scene: background, the page seen through [projectPage] (with
/// optional surface waves), uneven light, a hand, contrast and noise.
SceneResult renderScene(SceneSpec s, FlatPage page) {
  final rng = math.Random(s.seed);
  final w = s.width, h = s.height;
  final buf = _background(s, rng);
  Quad? truth;
  var partial = false;
  var fillsFrame = false;
  var focalPx = 0.0;

  if (s.hasDocument) {
    final (quad, focal) = projectPageWithFocal(s, page.width, page.height);
    focalPx = focal;
    truth = quad;
    final frame = Quad.frame(w, h);
    fillsFrame = frame.p.every((p) => _insideConvex(quad.p, p.x, p.y));
    partial =
        !fillsFrame &&
        quad.p.any((p) => p.x < 0 || p.y < 0 || p.x > w || p.y > h);
    if (fillsFrame) truth = frame;

    final srcRect = [
      const Pt(0, 0),
      Pt(page.width.toDouble(), 0),
      Pt(page.width.toDouble(), page.height.toDouble()),
      Pt(0, page.height.toDouble()),
    ];
    final hMat = homographyFromPoints(srcRect, quad.p);
    final inv = invert3x3(hMat);
    final scaleHint = math.sqrt(quad.area / (page.width * page.height));

    // Drop shadow: the same outline, shifted, darkening the background.
    final off = 0.006 * w;
    final shadow = [for (final p in quad.p) Pt(p.x + off, p.y + off * 1.3)];
    final waves = _Waves(rng, s.crumple, page.width.toDouble());

    final minX = quad.p.map((p) => p.x).reduce(math.min).floor() - 4;
    final maxX = quad.p.map((p) => p.x).reduce(math.max).ceil() + 4;
    final minY = quad.p.map((p) => p.y).reduce(math.min).floor() - 4;
    final maxY = quad.p.map((p) => p.y).reduce(math.max).ceil() + 4;
    final x0 = math.max(0, minX), x1 = math.min(w - 1, maxX);
    final y0 = math.max(0, minY), y1 = math.min(h - 1, maxY);
    final margin = 1.5 / scaleHint;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final o = (y * w + x) * 3;
        if (_insideConvex(shadow, x + 0.5, y + 0.5)) {
          buf[o] = (buf[o] * 0.62).round();
          buf[o + 1] = (buf[o + 1] * 0.62).round();
          buf[o + 2] = (buf[o + 2] * 0.62).round();
        }
        final pp = applyHomography(inv, Pt(x + 0.5, y + 0.5));
        if (pp.x < -margin ||
            pp.y < -margin ||
            pp.x > page.width + margin ||
            pp.y > page.height + margin) {
          continue;
        }
        final d = waves.displacement(pp.x, pp.y);
        final sx = (pp.x + d.$1).clamp(0.0, page.width - 1.001);
        final sy = (pp.y + d.$2).clamp(0.0, page.height - 1.001);
        final ix = sx.floor(), iy = sy.floor();
        final fx = sx - ix, fy = sy - iy;
        final shade = waves.shade(pp.x, pp.y);
        final edge = math.min(
          math.min(pp.x, page.width - pp.x),
          math.min(pp.y, page.height - pp.y),
        );
        final cover = ((edge * scaleHint) + 0.5).clamp(0.0, 1.0);
        if (cover <= 0) continue;
        for (var c = 0; c < 3; c++) {
          double px(int i, int j) =>
              page.rgb[(j * page.width + i) * 3 + c].toDouble();
          final top = px(ix, iy) * (1 - fx) + px(ix + 1, iy) * fx;
          final bottom = px(ix, iy + 1) * (1 - fx) + px(ix + 1, iy + 1) * fx;
          final v = (top * (1 - fy) + bottom * fy) * shade;
          buf[o + c] = (buf[o + c] * (1 - cover) + v * cover)
              .clamp(0, 255)
              .round();
        }
      }
    }
  }

  if (s.hand && truth != null) _drawHand(buf, w, h, truth, rng);

  // Uneven light: a slow gradient and an optional soft shadow band.
  final lightAngle = rng.nextDouble() * 2 * math.pi;
  final lc = math.cos(lightAngle), ls = math.sin(lightAngle);
  final bandAngle = rng.nextDouble() * math.pi;
  final bc = math.cos(bandAngle), bs = math.sin(bandAngle);
  final bandCentre = (rng.nextDouble() - 0.5) * 0.5;
  final bandHalf = 0.08 + rng.nextDouble() * 0.1;
  final gauss = _Gauss(rng);
  var o = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var gain =
          1 + s.lightGradient * 2 * ((x / w - 0.5) * lc + (y / h - 0.5) * ls);
      if (s.shadowBand) {
        final t = ((x - w / 2) * bc + (y - h / 2) * bs) / w - bandCentre;
        final band = 1 - _smoothstep(bandHalf, bandHalf + 0.06, t.abs());
        gain *= 1 - 0.5 * band;
      }
      for (var c = 0; c < 3; c++) {
        var v = buf[o + c] * gain;
        v = 128 + (v - 128) * s.contrast + (1 - s.contrast) * 12;
        if (s.noise > 0) v += gauss.next() * s.noise;
        buf[o + c] = v.clamp(0, 255).round();
      }
      o += 3;
    }
  }

  final image = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: buf.buffer,
    numChannels: 3,
  );
  return SceneResult(
    image: image,
    truth: truth,
    partial: partial,
    fillsFrame: fillsFrame,
    focalPx: focalPx,
  );
}

/// Smooth surface waves for a crumpled page: a displacement of where the page
/// is sampled, and a shading that imitates folds catching the light.
class _Waves {
  _Waves(math.Random rng, this.amplitude, double pageWidth)
    : _p = List.generate(6, (_) => rng.nextDouble() * 2 * math.pi),
      _l1 = pageWidth * (0.12 + rng.nextDouble() * 0.1),
      _l2 = pageWidth * (0.2 + rng.nextDouble() * 0.15),
      _l3 = pageWidth * (0.07 + rng.nextDouble() * 0.06);

  final double amplitude;
  final List<double> _p;
  final double _l1, _l2, _l3;

  (double, double) displacement(double u, double v) {
    if (amplitude == 0) return (0, 0);
    final dx =
        amplitude *
        (math.sin(u / _l1 + _p[0]) +
            0.5 * math.sin(v / _l2 + _p[1]) +
            0.35 * math.sin((u + v) / _l3 + _p[2]));
    final dy =
        amplitude *
        (math.sin(v / _l1 + _p[3]) +
            0.5 * math.sin(u / _l2 + _p[4]) +
            0.35 * math.sin((u - v) / _l3 + _p[5]));
    return (dx, dy);
  }

  double shade(double u, double v) {
    if (amplitude == 0) return 1;
    final k = math.min(1.0, amplitude / 10);
    return 1 +
        0.10 * k * math.sin((u * 0.8 + v) / _l3 + _p[0]) +
        0.06 * k * math.sin((u - v * 0.6) / _l2 + _p[3]);
  }
}

/// A hand-coloured soft blob that covers an edge and a corner region of the
/// page (the page outline stays the truth; the hand hides what it hides).
void _drawHand(Uint8List buf, int w, int h, Quad quad, math.Random rng) {
  final edge = rng.nextInt(4);
  final a = quad.p[edge], b = quad.p[(edge + 1) % 4];
  final t = 0.25 + rng.nextDouble() * 0.5;
  final cx = a.x + (b.x - a.x) * t;
  final cy = a.y + (b.y - a.y) * t;
  // Push the blob a little outward from the page centre so it overlaps the
  // edge instead of covering the middle.
  final mx = quad.p.map((p) => p.x).reduce((p, q) => p + q) / 4;
  final my = quad.p.map((p) => p.y).reduce((p, q) => p + q) / 4;
  var ox = cx - mx, oy = cy - my;
  final len = math.sqrt(ox * ox + oy * oy);
  ox /= len;
  oy /= len;
  final blobs = <List<double>>[
    [
      cx + ox * 0.07 * w,
      cy + oy * 0.07 * w,
      0.13 * w,
      0.075 * w,
      math.atan2(oy, ox),
    ],
    [
      cx + ox * 0.14 * w - oy * 0.05 * w,
      cy + oy * 0.14 * w + ox * 0.05 * w,
      0.09 * w,
      0.03 * w,
      math.atan2(oy, ox) + 0.3,
    ],
    [
      cx + ox * 0.14 * w + oy * 0.05 * w,
      cy + oy * 0.14 * w - ox * 0.05 * w,
      0.09 * w,
      0.03 * w,
      math.atan2(oy, ox) - 0.3,
    ],
  ];
  for (final q in blobs) {
    final ca = math.cos(q[4]), sa = math.sin(q[4]);
    final reach = math.max(q[2], q[3]) * 1.2;
    final x0 = math.max(0, (q[0] - reach).floor());
    final x1 = math.min(w - 1, (q[0] + reach).ceil());
    final y0 = math.max(0, (q[1] - reach).floor());
    final y1 = math.min(h - 1, (q[1] + reach).ceil());
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final dx = x - q[0], dy = y - q[1];
        final u = (dx * ca + dy * sa) / q[2];
        final v = (-dx * sa + dy * ca) / q[3];
        final r2 = u * u + v * v;
        if (r2 >= 1.1) continue;
        final cover = 1 - _smoothstep(0.9, 1.1, r2);
        final shade = 0.92 + 0.1 * (1 - r2);
        final o = (y * w + x) * 3;
        buf[o] = (buf[o] * (1 - cover) + 226 * shade * cover).round();
        buf[o + 1] = (buf[o + 1] * (1 - cover) + 173 * shade * cover).round();
        buf[o + 2] = (buf[o + 2] * (1 - cover) + 142 * shade * cover).round();
      }
    }
  }
}
