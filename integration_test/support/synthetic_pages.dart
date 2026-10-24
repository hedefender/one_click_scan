import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

/// Invented documents for the OCR integration tests. Every name, number and
/// address is made up (`example.com`); no real document is ever used.
class SyntheticDocument {
  const SyntheticDocument(this.name, this.lines, this.keyTokens);

  final String name;
  final List<String> lines;

  /// Words and numbers the engine must find in the text.
  final List<String> keyTokens;
}

const greekReceipt = SyntheticDocument(
  'greek_receipt',
  [
    'ΕΤΑΙΡΕΙΑ ΠΑΡΑΔΕΙΓΜΑ ΑΕ',
    'Οδός Δοκιμής 15, Αθήνα',
    'ΑΦΜ 123456789',
    'Απόδειξη λιανικής πώλησης 000482',
    'Ημερομηνία 12/03/2026',
    'Γάλα φρέσκο 1 λίτρο 1,45',
    'Ψωμί ολικής άλεσης 2,30',
    'Ελαιόλαδο extra virgin 7,90',
    'Ευχαριστούμε για την προτίμηση',
    'Total amount 45,90 EUR',
    'Email info@example.com',
  ],
  [
    'ΠΑΡΑΔΕΙΓΜΑ',
    'Δοκιμής',
    'Αθήνα',
    '123456789',
    '000482',
    '12/03/2026',
    'Γάλα',
    'Ψωμί',
    'Ελαιόλαδο',
    'Ευχαριστούμε',
    'Total',
    '45,90',
    'EUR',
    'info@example.com',
  ],
);

const latinAccents = SyntheticDocument(
  'latin_accents',
  [
    'Müller Straße Größe Übung',
    'Café crème brûlée à la française',
    'Año nuevo, niño y señor',
    'Città perché così più',
    'Informação coração não',
    'Invoice number 20260312 total 128.40',
  ],
  [
    'Müller',
    'Straße',
    'Größe',
    'Übung',
    'Café',
    'crème',
    'brûlée',
    'française',
    'Año',
    'niño',
    'señor',
    'Città',
    'perché',
    'così',
    'più',
    'Informação',
    'coração',
    'não',
    '20260312',
    '128.40',
  ],
);

/// Share of [tokens] that appear in [text] (case-insensitive, spaces
/// collapsed). Only the share is reported, never the text.
double keyRecall(String text, List<String> tokens) {
  String norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  final haystack = norm(text);
  final found = tokens.where((t) => haystack.contains(norm(t))).length;
  return found / tokens.length;
}

/// Draws the document with the system font (Roboto on Android has Latin,
/// Greek and Cyrillic) on white, black text.
Future<img.Image> renderDocument(
  List<String> lines, {
  int width = 1240,
  double fontSize = 36,
}) async {
  final lineHeight = fontSize * 1.9;
  final height = (lineHeight * lines.length + 2 * fontSize).round();
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  for (var i = 0; i < lines.length; i++) {
    final painter = TextPainter(
      text: TextSpan(
        text: lines[i],
        style: TextStyle(
          color: const ui.Color(0xFF000000),
          fontSize: fontSize,
          fontFamily: 'Roboto',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width - 2 * fontSize);
    painter.paint(canvas, ui.Offset(fontSize, fontSize + i * lineHeight));
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return img.Image.fromBytes(
    width: width,
    height: height,
    bytes: data!.buffer,
    numChannels: 4,
  ).convert(numChannels: 3);
}

/// The pixels a camera would store so that EXIF [orientation] shows
/// [upright] the right way up (the inverse of the tag's transform).
img.Image storedFor(img.Image upright, int orientation) {
  return switch (orientation) {
    2 => img.flipHorizontal(upright.clone()),
    3 => img.copyRotate(upright, angle: 180),
    4 => img.flipVertical(upright.clone()),
    // Transpose and transverse are their own inverses.
    5 => img.flipHorizontal(img.copyRotate(upright, angle: 90)),
    6 => img.copyRotate(upright, angle: 270),
    7 => img.flipHorizontal(img.copyRotate(upright, angle: 270)),
    8 => img.copyRotate(upright, angle: 90),
    _ => upright.clone(),
  };
}

/// Writes [image] as a JPEG; [exifOrientation] (any value, including the
/// invalid 0) is stored in the EXIF block.
File writeJpeg(
  String path,
  img.Image image, {
  int? exifOrientation,
  int quality = 92,
}) {
  final copy = image.clone();
  if (exifOrientation != null) copy.exif.imageIfd.orientation = exifOrientation;
  return File(path)..writeAsBytesSync(img.encodeJpg(copy, quality: quality));
}

/// A file that is only the header of a huge JPEG (SOI and SOF0 with the
/// given size). Enough for the size check; it can never be decoded, so
/// nothing can run out of memory by accident.
File writeFakeHugeJpeg(String path, {required int width, required int height}) {
  final bytes = <int>[
    0xFF, 0xD8, // SOI
    0xFF, 0xC0, 0x00, 0x11, 0x08, // SOF0, length 17, 8 bits
    height >> 8, height & 0xFF, width >> 8, width & 0xFF,
    0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
    0xFF, 0xD9, // EOI
  ];
  return File(path)..writeAsBytesSync(bytes);
}

/// Pen-like strokes (no letters): what the engine sees on a page of
/// handwriting it cannot read. Deterministic.
Future<img.Image> renderScribbles({int width = 1240, int height = 700}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final pen = ui.Paint()
    ..color = const ui.Color(0xFF202020)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 4
    ..strokeCap = ui.StrokeCap.round;
  var seed = 12345;
  double next() {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    return seed / 0x7FFFFFFF;
  }

  for (var row = 0; row < 8; row++) {
    final baseline = 80.0 + row * 75;
    final path = ui.Path()..moveTo(60, baseline);
    var x = 60.0;
    while (x < width - 80) {
      final dx = 12 + next() * 18;
      path.quadraticBezierTo(
        x + dx / 2,
        baseline - 20 - next() * 28,
        x + dx,
        baseline + (next() - 0.5) * 16,
      );
      x += dx;
    }
    canvas.drawPath(path, pen);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return img.Image.fromBytes(
    width: width,
    height: height,
    bytes: data!.buffer,
    numChannels: 4,
  ).convert(numChannels: 3);
}

/// A 4000 x 3000 (12 MP) photo with [page] pasted on white, like a camera
/// shot of a document: large enough for the native decode.
File writeBigPhoto(String dir, img.Image page, {int? exifOrientation}) {
  final big = img.Image(width: 4000, height: 3000, numChannels: 3);
  img.fill(big, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(big, img.copyResize(page, width: 3000), dstX: 500);
  return writeJpeg(
    '$dir/big.jpg',
    big,
    exifOrientation: exifOrientation,
    quality: 85,
  );
}
