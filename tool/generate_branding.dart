// Generates the Android launcher icon and splash resources from the two source
// images in assets/branding/. Run from the repository root:
//
//   dart run tool/generate_branding.dart
//
// Sources (JPEG, `.jfif`):
//   icon_original.jfif          the finished icon: symbol on a dark rounded plate
//   icon_foreground_green.jfif  the same symbol on a solid green background
//
// Outputs (all under android/app/src/main/res/, committed to the repository):
//   drawable-*dpi/ic_launcher_foreground.png   chroma-keyed symbol, 108dp canvas,
//                                              scaled into the adaptive safe zone
//   drawable/ic_launcher_background.xml        radial gradient (no image)
//   mipmap-anydpi-v26/ic_launcher.xml          adaptive icon (Android 8+)
//   mipmap-*dpi/ic_launcher.png                legacy icon (Android 7.x)
//   drawable-*dpi/splash_icon.png              splash icon, 288dp canvas
//   values/colors.xml                          splash background colour
//
// Needs the dev dependency `image` (pure Dart, no native tools). The rules the
// numbers come from are in docs/DECISIONS.md (ADR-009) and the asset test in
// test/branding/branding_assets_test.dart.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const _res = 'android/app/src/main/res';
const _originalPath = 'assets/branding/icon_original.jfif';
const _foregroundPath = 'assets/branding/icon_foreground_green.jfif';

/// Android density buckets and their scale against mdpi.
const _densities = <String, double>{
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

// Chroma key. spill = G - max(R, B). The matte is fully background from
// `_spillClear` up, fully symbol from `_spillOpaque` down, linear in between.
// Edge pixels (alpha < 1) get G capped at max(R, B) + `_despillMargin`, so no
// green fringe is left. The turquoise glows (laser, lens) have a spill below
// `_spillOpaque` and stay untouched.
const _spillOpaque = 30;
const _spillClear = 110;
const _despillMargin = 6;

// Edge decontamination: pixels closer than `_edgeSolid` to the background take
// their colour from solid pixels within `_edgeReach`.
const _edgeSolid = 3;
const _edgeReach = 5;

// Adaptive icon: 108dp canvas, the safe zone is a circle of 66dp.
const _adaptiveCanvasDp = 108;
const _adaptiveSafeDiameterDp = 66;

// The 1% keeps resampling and whole-pixel placement inside the circle.
const _safeZoneMargin = 0.99;

// Adaptive background gradient, sampled from icon_original: the plate colour
// next to the symbol (centre) and at the plate edge, which is also the colour
// of the frame around the plate.
const _gradientCenter = '#172A5C';
const _gradientEdge = '#12183C';

// Splash: the system shows the icon in a circle of 192dp on a 288dp canvas
// (Android 12+, icon without its own background). The whole plate must stay
// inside it. `_plateRadiusPx` is the farthest corner of the rounded plate from
// the image centre, measured on the 2048px original, with a little margin.
const _splashCanvasDp = 288;
const _splashCircleDiameterDp = 192;
const _plateRadiusPx = 1060.0;
const _splashPlateRadiusDp = 90.0;

void main() {
  final original = _decode(_originalPath);
  final foreground = _decode(_foregroundPath);

  _writeAdaptiveForeground(_keyGreen(foreground));
  _writeText('$_res/drawable/ic_launcher_background.xml', _backgroundXml);
  _writeText('$_res/mipmap-anydpi-v26/ic_launcher.xml', _adaptiveXml);
  _writeLegacyIcons(original);

  final frame = _frameColor(original);
  _writeSplash(original, frame);
  _writeText('$_res/values/colors.xml', _colorsXml(frame));
}

img.Image _decode(String path) {
  final image = img.decodeJpg(File(path).readAsBytesSync());
  if (image == null) {
    throw StateError('Cannot read $path');
  }
  return image;
}

void _writeText(String path, String content) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}

void _writePng(String path, img.Image image) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image, level: 9));
}

// --- Chroma key -------------------------------------------------------------

/// Returns an RGBA copy (not premultiplied) with a real alpha channel.
img.Image _keyGreen(img.Image source) {
  final w = source.width, h = source.height;
  final alpha = Float32List(w * h);
  final rgb = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = source.getPixel(x, y);
      var r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
      final spill = g - math.max(r, b);
      final a = ((_spillClear - spill) / (_spillClear - _spillOpaque)).clamp(
        0.0,
        1.0,
      );
      if (a < 1.0) {
        g = math.min(g, math.max(r, b) + _despillMargin);
      }
      final i = y * w + x;
      alpha[i] = a;
      rgb[i * 3] = r;
      rgb[i * 3 + 1] = g;
      rgb[i * 3 + 2] = b;
    }
  }
  _fillEnclosedHoles(source, alpha, rgb);
  _decontaminateEdges(alpha, rgb, w, h);

  final out = img.Image(width: w, height: h, numChannels: 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      out.setPixelRgba(
        x,
        y,
        rgb[i * 3],
        rgb[i * 3 + 1],
        rgb[i * 3 + 2],
        (alpha[i] * 255).round(),
      );
    }
  }
  return out;
}

/// Bright mint highlights (the laser core) have a spill inside the matte's
/// transition range. They are not background: background is only what the
/// image border can reach through not-fully-opaque pixels. Everything else that
/// is not fully opaque is enclosed by the symbol and becomes solid again, with
/// its original colour.
void _fillEnclosedHoles(img.Image source, Float32List alpha, Uint8List rgb) {
  final w = source.width, h = source.height;
  final reached = Uint8List(w * h);
  final stack = Int32List(w * h);
  var top = 0;
  void visit(int x, int y) {
    final i = y * w + x;
    if (reached[i] == 1 || alpha[i] >= 1) return;
    reached[i] = 1;
    stack[top++] = i;
  }

  for (var x = 0; x < w; x++) {
    visit(x, 0);
    visit(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    visit(0, y);
    visit(w - 1, y);
  }
  while (top > 0) {
    final i = stack[--top];
    final x = i % w, y = i ~/ w;
    if (x > 0) visit(x - 1, y);
    if (x < w - 1) visit(x + 1, y);
    if (y > 0) visit(x, y - 1);
    if (y < h - 1) visit(x, y + 1);
  }
  for (var i = 0; i < alpha.length; i++) {
    if (alpha[i] >= 1 || reached[i] == 1) continue;
    final p = source.getPixel(i % w, i ~/ w);
    alpha[i] = 1;
    rgb[i * 3] = p.r.toInt();
    rgb[i * 3 + 1] = p.g.toInt();
    rgb[i * 3 + 2] = p.b.toInt();
  }
}

/// Pixels next to the background are a blend of symbol and green. Where the
/// symbol is blue that blend is cyan, and the spill test does not see it. Their
/// colour is replaced by the mean of the solid symbol pixels around them.
/// Features thinner than the ring (tail, sparks) have no such pixels and keep
/// their colour.
void _decontaminateEdges(Float32List alpha, Uint8List rgb, int w, int h) {
  // Chamfer distance (in pixels) to the nearest fully transparent pixel,
  // capped: only values up to `_edgeSolid` matter.
  final dist = Uint8List(w * h);
  for (var i = 0; i < dist.length; i++) {
    dist[i] = alpha[i] == 0 ? 0 : _edgeSolid;
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      var d = dist[i];
      if (x > 0) d = math.min(d, dist[i - 1] + 1);
      if (y > 0) {
        d = math.min(d, dist[i - w] + 1);
        if (x > 0) d = math.min(d, dist[i - w - 1] + 1);
        if (x < w - 1) d = math.min(d, dist[i - w + 1] + 1);
      }
      dist[i] = d;
    }
  }
  for (var y = h - 1; y >= 0; y--) {
    for (var x = w - 1; x >= 0; x--) {
      final i = y * w + x;
      var d = dist[i];
      if (x < w - 1) d = math.min(d, dist[i + 1] + 1);
      if (y < h - 1) {
        d = math.min(d, dist[i + w] + 1);
        if (x < w - 1) d = math.min(d, dist[i + w + 1] + 1);
        if (x > 0) d = math.min(d, dist[i + w - 1] + 1);
      }
      dist[i] = d;
    }
  }

  final fixed = Uint8List.fromList(rgb);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      if (alpha[i] == 0 || dist[i] >= _edgeSolid) continue;
      var r = 0, g = 0, b = 0, n = 0;
      for (var dy = -_edgeReach; dy <= _edgeReach; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -_edgeReach; dx <= _edgeReach; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= w) continue;
          final j = yy * w + xx;
          if (dist[j] < _edgeSolid || alpha[j] < 1) continue;
          r += rgb[j * 3];
          g += rgb[j * 3 + 1];
          b += rgb[j * 3 + 2];
          n++;
        }
      }
      if (n < 4) continue;
      fixed[i * 3] = r ~/ n;
      fixed[i * 3 + 1] = g ~/ n;
      fixed[i * 3 + 2] = b ~/ n;
    }
  }
  rgb.setAll(0, fixed);
}

// --- Adaptive icon ----------------------------------------------------------

/// Smallest circle that holds every opaque pixel (alpha >= 0.5). Only the
/// outline pixels (first and last opaque pixel of each row and column) matter.
({double x, double y, double r}) _enclosingCircle(img.Image keyed) {
  final points = <math.Point<double>>[];
  for (var y = 0; y < keyed.height; y++) {
    int? first, last;
    for (var x = 0; x < keyed.width; x++) {
      if (keyed.getPixel(x, y).a >= 128) {
        first ??= x;
        last = x;
      }
    }
    if (first != null) {
      points
        ..add(math.Point(first.toDouble(), y.toDouble()))
        ..add(math.Point(last!.toDouble(), y.toDouble()));
    }
  }
  for (var x = 0; x < keyed.width; x++) {
    int? first, last;
    for (var y = 0; y < keyed.height; y++) {
      if (keyed.getPixel(x, y).a >= 128) {
        first ??= y;
        last = y;
      }
    }
    if (first != null) {
      points
        ..add(math.Point(x.toDouble(), first.toDouble()))
        ..add(math.Point(x.toDouble(), last!.toDouble()));
    }
  }
  return _welzl(points);
}

/// Randomised incremental smallest enclosing circle.
({double x, double y, double r}) _welzl(List<math.Point<double>> input) {
  final pts = [...input]..shuffle(math.Random(42));
  var c = pts.first;
  var r = 0.0;
  const eps = 1e-7;
  bool outside(math.Point<double> p) => c.distanceTo(p) > r + eps;

  for (var i = 1; i < pts.length; i++) {
    if (!outside(pts[i])) continue;
    c = pts[i];
    r = 0;
    for (var j = 0; j < i; j++) {
      if (!outside(pts[j])) continue;
      c = (pts[i] + pts[j]) * 0.5;
      r = pts[i].distanceTo(pts[j]) / 2;
      for (var k = 0; k < j; k++) {
        if (!outside(pts[k])) continue;
        final cc = _circumcircle(pts[i], pts[j], pts[k]);
        c = cc.$1;
        r = cc.$2;
      }
    }
  }
  return (x: c.x, y: c.y, r: r);
}

(math.Point<double>, double) _circumcircle(
  math.Point<double> a,
  math.Point<double> b,
  math.Point<double> c,
) {
  final d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y));
  if (d.abs() < 1e-12) {
    // Collinear: the circle on the two farthest points.
    final pairs = [(a, b), (a, c), (b, c)]
      ..sort((p, q) => q.$1.distanceTo(q.$2).compareTo(p.$1.distanceTo(p.$2)));
    final p = pairs.first;
    return ((p.$1 + p.$2) * 0.5, p.$1.distanceTo(p.$2) / 2);
  }
  final a2 = a.x * a.x + a.y * a.y;
  final b2 = b.x * b.x + b.y * b.y;
  final c2 = c.x * c.x + c.y * c.y;
  final ux = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d;
  final uy = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d;
  final center = math.Point(ux, uy);
  return (center, center.distanceTo(a));
}

img.Image _premultiply(img.Image keyed) {
  final out = img.Image(
    width: keyed.width,
    height: keyed.height,
    numChannels: 4,
  );
  for (var y = 0; y < keyed.height; y++) {
    for (var x = 0; x < keyed.width; x++) {
      final p = keyed.getPixel(x, y);
      final a = p.a / 255;
      out.setPixelRgba(
        x,
        y,
        (p.r * a).round(),
        (p.g * a).round(),
        (p.b * a).round(),
        p.a.toInt(),
      );
    }
  }
  return out;
}

void _unpremultiplyInPlace(img.Image image) {
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final p = image.getPixel(x, y);
      final a = p.a.toInt();
      if (a == 0) {
        image.setPixelRgba(x, y, 0, 0, 0, 0);
      } else if (a < 255) {
        final f = 255 / a;
        image.setPixelRgba(
          x,
          y,
          math.min(255, (p.r * f).round()),
          math.min(255, (p.g * f).round()),
          math.min(255, (p.b * f).round()),
          a,
        );
      }
    }
  }
}

void _writeAdaptiveForeground(img.Image keyed) {
  final circle = _enclosingCircle(keyed);
  final premultiplied = _premultiply(keyed);
  final safeRadiusFraction = _adaptiveSafeDiameterDp / 2 / _adaptiveCanvasDp;
  stdout.writeln(
    'Symbol outline: enclosing circle r=${circle.r.toStringAsFixed(1)}px '
    'at (${circle.x.toStringAsFixed(1)}, ${circle.y.toStringAsFixed(1)}) '
    'of ${keyed.width}px; safe zone radius '
    '${(safeRadiusFraction * 100).toStringAsFixed(1)}% of the canvas.',
  );

  for (final entry in _densities.entries) {
    final canvas = (_adaptiveCanvasDp * entry.value).round();
    final scale = canvas * safeRadiusFraction * _safeZoneMargin / circle.r;
    final size = (keyed.width * scale).round();
    final scaled = img.copyResize(
      premultiplied,
      width: size,
      height: size,
      interpolation: img.Interpolation.average,
    );
    // Put the circle centre on the canvas centre.
    final dx = (canvas / 2 - circle.x * scale).round();
    final dy = (canvas / 2 - circle.y * scale).round();
    final out = img.Image(width: canvas, height: canvas, numChannels: 4);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final ox = x + dx, oy = y + dy;
        if (ox < 0 || oy < 0 || ox >= canvas || oy >= canvas) continue;
        final p = scaled.getPixel(x, y);
        out.setPixelRgba(
          ox,
          oy,
          p.r.toInt(),
          p.g.toInt(),
          p.b.toInt(),
          p.a.toInt(),
        );
      }
    }
    _unpremultiplyInPlace(out);
    _writePng('$_res/drawable-${entry.key}/ic_launcher_foreground.png', out);
    stdout.writeln(
      '  ${entry.key}: ${canvas}px canvas, symbol at '
      '${(scale / (canvas / keyed.width) * 100).toStringAsFixed(1)}% of its '
      'size in the source image',
    );
  }
}

const _backgroundXml =
    '''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/generate_branding.dart. Adaptive icon background:
     radial gradient with the colours of the original icon plate. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path android:pathData="M0,0h108v108h-108z">
        <aapt:attr name="android:fillColor">
            <gradient
                android:type="radial"
                android:centerX="54"
                android:centerY="54"
                android:gradientRadius="64"
                android:startColor="$_gradientCenter"
                android:endColor="$_gradientEdge" />
        </aapt:attr>
    </path>
</vector>
''';

const _adaptiveXml = '''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/generate_branding.dart. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
''';

// --- Legacy icon ------------------------------------------------------------

void _writeLegacyIcons(img.Image original) {
  for (final entry in _densities.entries) {
    final size = (48 * entry.value).round();
    final icon = img.copyResize(
      original,
      width: size,
      height: size,
      interpolation: img.Interpolation.average,
    );
    _writePng('$_res/mipmap-${entry.key}/ic_launcher.png', icon);
  }
}

// --- Splash -----------------------------------------------------------------

/// The dark frame around the plate: median of the outer 40px of the original.
({int r, int g, int b}) _frameColor(img.Image original) {
  final rs = <int>[], gs = <int>[], bs = <int>[];
  const band = 40;
  for (var y = 0; y < original.height; y++) {
    for (var x = 0; x < original.width; x++) {
      final inBand =
          x < band ||
          y < band ||
          x >= original.width - band ||
          y >= original.height - band;
      if (!inBand) continue;
      final p = original.getPixel(x, y);
      rs.add(p.r.toInt());
      gs.add(p.g.toInt());
      bs.add(p.b.toInt());
    }
  }
  int median(List<int> v) => (v..sort())[v.length ~/ 2];
  return (r: median(rs), g: median(gs), b: median(bs));
}

String _hex(({int r, int g, int b}) c) =>
    '#${c.r.toRadixString(16).padLeft(2, '0')}'
            '${c.g.toRadixString(16).padLeft(2, '0')}'
            '${c.b.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();

String _colorsXml(({int r, int g, int b}) frame) =>
    '''<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/generate_branding.dart. -->
<resources>
    <!-- The dark frame around the plate of the original icon, so the splash
         icon blends into its background. Same in light and dark mode. -->
    <color name="splash_background">${_hex(frame)}</color>
</resources>
''';

/// The original icon, scaled so the whole plate sits inside the circle the
/// system masks the splash icon with, on a transparent 288dp canvas. The image
/// fades out at the circle, where its frame has the splash background colour.
void _writeSplash(img.Image original, ({int r, int g, int b}) frame) {
  final dpPerPixel = _splashPlateRadiusDp / _plateRadiusPx;
  const circleRadius = _splashCircleDiameterDp / 2;
  for (final entry in _densities.entries) {
    final density = entry.value;
    final canvas = (_splashCanvasDp * density).round();
    final size = (original.width * dpPerPixel * density).round();
    final scaled = img.copyResize(
      original,
      width: size,
      height: size,
      interpolation: img.Interpolation.average,
    );
    final offset = (canvas - size) ~/ 2;
    final out = img.Image(width: canvas, height: canvas, numChannels: 4);
    for (var y = 0; y < canvas; y++) {
      for (var x = 0; x < canvas; x++) {
        final dx = (x + 0.5 - canvas / 2) / density;
        final dy = (y + 0.5 - canvas / 2) / density;
        final d = math.sqrt(dx * dx + dy * dy);
        final alpha =
            ((circleRadius - d) / (circleRadius - _splashPlateRadiusDp)).clamp(
              0.0,
              1.0,
            );
        if (alpha == 0) continue;
        final sx = x - offset, sy = y - offset;
        var r = frame.r, g = frame.g, b = frame.b;
        if (sx >= 0 && sy >= 0 && sx < size && sy < size) {
          final p = scaled.getPixel(sx, sy);
          r = p.r.toInt();
          g = p.g.toInt();
          b = p.b.toInt();
        }
        out.setPixelRgba(x, y, r, g, b, (alpha * 255).round());
      }
    }
    _writePng('$_res/drawable-${entry.key}/splash_icon.png', out);
  }
  stdout.writeln('Splash background ${_hex(frame)}');
}
