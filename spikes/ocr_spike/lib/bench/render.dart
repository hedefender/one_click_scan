import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

import 'synthetic_docs.dart';

/// Capture conditions applied to a clean render.
enum Condition {
  clean,
  rot3,
  rotMinus3,
  blur,
  lowContrastNoise,
  rot90Exif,
  rot90Raw,
  big,
}

extension ConditionName on Condition {
  String get label => switch (this) {
    Condition.clean => 'clean',
    Condition.rot3 => 'rot+3',
    Condition.rotMinus3 => 'rot-3',
    Condition.blur => 'blur',
    Condition.lowContrastNoise => 'lowcontrast+noise',
    Condition.rot90Exif => 'rot90_exif',
    Condition.rot90Raw => 'rot90_raw',
    Condition.big => 'big2x',
  };
}

/// Draws [spec] with the bundled fonts: black text on white, like a scan.
Future<img.Image> renderDoc(DocSpec spec) async {
  const margin = 40.0;
  final painters = <(TextPainter, Cell, double)>[];
  var y = margin;
  final lineGap = spec.size * 0.55;
  for (final row in spec.rows) {
    if (row == null) {
      y += spec.size * 1.1;
      continue;
    }
    var rowHeight = 0.0;
    for (final cell in row) {
      if (cell.text.isEmpty) continue;
      final painter = TextPainter(
        text: TextSpan(
          text: cell.text,
          style: TextStyle(
            fontFamily: spec.font,
            fontSize: cell.size ?? spec.size,
            fontWeight: cell.bold ? FontWeight.w700 : FontWeight.w400,
            color: const ui.Color(0xFF000000),
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painters.add((painter, cell, y));
      rowHeight = math.max(rowHeight, painter.height);
    }
    y += rowHeight + lineGap;
  }
  final height = (y + margin).ceil();
  final width = spec.width.ceil();

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  for (final (painter, cell, top) in painters) {
    final left = cell.right
        ? cell.x - painter.width
        : cell.center
        ? cell.x - painter.width / 2
        : cell.x;
    painter.paint(canvas, ui.Offset(left, top));
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return img.Image.fromBytes(
    width: width,
    height: height,
    bytes: data!.buffer,
    numChannels: 4,
  ).convert(numChannels: 3);
}

/// Returns the JPEG bytes of [clean] after [condition]. [seed] keeps the noise
/// reproducible.
List<int> applyCondition(img.Image clean, Condition condition, int seed) {
  var out = clean.clone();
  switch (condition) {
    case Condition.clean:
      break;
    case Condition.rot3:
      out = _rotateOnWhite(out, 3);
    case Condition.rotMinus3:
      out = _rotateOnWhite(out, -3);
    case Condition.blur:
      out = img.gaussianBlur(out, radius: 3);
    case Condition.lowContrastNoise:
      out = _lowContrastNoise(out, seed);
    case Condition.rot90Exif:
      out = img.copyRotate(out, angle: 270);
      out.exif.imageIfd.orientation = 6;
    case Condition.rot90Raw:
      out = img.copyRotate(out, angle: 270);
    case Condition.big:
      // About the pixel count of a phone camera (12 to 16 MP for A4 pages).
      out = img.copyResize(
        out,
        width: out.width * 2,
        interpolation: img.Interpolation.cubic,
      );
  }
  return img.encodeJpg(out, quality: 90);
}

/// "Bad capture" for the timing scenarios: slight tilt, blur and low contrast
/// with noise together.
img.Image degradePoor(img.Image clean, int seed) {
  var out = _rotateOnWhite(clean.clone(), 2);
  out = img.gaussianBlur(out, radius: 2);
  return _lowContrastNoise(out, seed);
}

img.Image _rotateOnWhite(img.Image src, num angle) {
  final rgba = src.convert(numChannels: 4);
  final rotated = img.copyRotate(
    rgba,
    angle: angle,
    interpolation: img.Interpolation.cubic,
  );
  final canvas = img.Image(
    width: rotated.width,
    height: rotated.height,
    numChannels: 4,
  );
  img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 255));
  img.compositeImage(canvas, rotated);
  return canvas.convert(numChannels: 3);
}

img.Image _lowContrastNoise(img.Image src, int seed) {
  final random = math.Random(seed);
  double gauss() {
    final u1 = 1 - random.nextDouble(), u2 = random.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }

  for (final p in src) {
    final n = gauss() * 14;
    // Dark grey on light grey: black -> 105, white -> 205, plus noise.
    for (var c = 0; c < 3; c++) {
      final v = p[c].toDouble();
      final out = 105 + v * (100 / 255) + n;
      p[c] = out.clamp(0, 255);
    }
  }
  return src;
}

Future<File> writeJpeg(Directory dir, String name, List<int> bytes) async {
  await dir.create(recursive: true);
  final file = File('${dir.path}/$name.jpg');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}
