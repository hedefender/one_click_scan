import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

/// One line of an invented document.
class SheetLine {
  const SheetLine(this.text, this.size);

  final String text;
  final double size;
}

/// An invented document: every name, number and address is made up.
class SheetSpec {
  const SheetSpec(
    this.name,
    this.lines, {
    this.tiltDegrees = 0,
    this.noise = 0,
  });

  final String name;
  final List<SheetLine> lines;
  final double tiltDegrees;

  /// Standard deviation of camera-like noise (0 = clean render).
  final double noise;
}

/// Where a character really is, in the final picture, along its line.
class TruthChar {
  TruthChar(this.ch, this.x0, this.x1);

  final String ch;

  /// Distance from the line origin along the text direction, pixels.
  final double x0, x1;
}

class TruthLine {
  TruthLine(this.text, this.ox, this.oy, this.angle, this.height, this.chars);

  final String text;

  /// Left end of the vertical middle of the line, in the final picture.
  final double ox, oy;

  /// Text direction (radians, y down).
  final double angle;
  final double height;
  final List<TruthChar> chars;

  Map<String, Object?> toJson() => {
    'text': text,
    'ox': ox,
    'oy': oy,
    'angle': angle,
    'height': height,
    'chars': [
      for (final c in chars) [c.ch, c.x0, c.x1],
    ],
  };
}

class RenderedSheet {
  RenderedSheet(this.image, this.truth);

  final img.Image image;
  final List<TruthLine> truth;

  Map<String, Object?> toJson(String name) => {
    'name': name,
    'width': image.width,
    'height': image.height,
    'lines': [for (final l in truth) l.toJson()],
  };
}

/// Draws [spec] on white with the system font and records where every
/// character landed.
Future<RenderedSheet> renderSheet(SheetSpec spec, {int width = 1240}) async {
  const margin = 60.0;
  var y = margin;
  final painters = <TextPainter>[];
  final ys = <double>[];
  for (final line in spec.lines) {
    final p = TextPainter(
      text: TextSpan(
        text: line.text,
        style: TextStyle(
          color: const ui.Color(0xFF111111),
          fontSize: line.size,
          fontFamily: 'Roboto',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painters.add(p);
    ys.add(y);
    y += p.height + line.size * 0.9;
  }
  final height = (y + margin).round();
  final angle = spec.tiltDegrees * math.pi / 180;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  canvas.save();
  canvas.translate(width / 2, height / 2);
  canvas.rotate(angle);
  canvas.translate(-width / 2, -height / 2);
  for (var i = 0; i < painters.length; i++) {
    painters[i].paint(canvas, ui.Offset(margin, ys[i]));
  }
  canvas.restore();
  final picture = recorder.endRecording();
  final raster = await picture.toImage(width, height);
  final data = await raster.toByteData(format: ui.ImageByteFormat.rawRgba);
  raster.dispose();
  picture.dispose();
  var image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: data!.buffer,
    numChannels: 4,
  ).convert(numChannels: 3);

  if (spec.noise > 0) image = _photoLike(image, spec.noise);

  // Truth: rotate each line's origin about the centre like the canvas did.
  final cs = math.cos(angle), sn = math.sin(angle);
  final truth = <TruthLine>[];
  for (var i = 0; i < painters.length; i++) {
    final p = painters[i];
    final text = spec.lines[i].text;
    final chars = <TruthChar>[];
    for (var k = 0; k < text.length; k++) {
      final boxes = p.getBoxesForSelection(
        TextSelection(baseOffset: k, extentOffset: k + 1),
      );
      if (boxes.isEmpty) continue;
      chars.add(TruthChar(text[k], boxes.first.left, boxes.first.right));
    }
    final dx = margin - width / 2, dy = ys[i] + p.height / 2 - height / 2;
    truth.add(
      TruthLine(
        text,
        width / 2 + dx * cs - dy * sn,
        height / 2 + dx * sn + dy * cs,
        angle,
        p.height,
        chars,
      ),
    );
  }
  return RenderedSheet(image, truth);
}

/// Camera-like: a soft shadow across the page and grain.
img.Image _photoLike(img.Image src, double noise) {
  final rnd = math.Random(7);
  final out = src.clone();
  final w = out.width, h = out.height;
  for (final p in out) {
    final shade = 1 - 0.18 * ((p.x / w) * 0.6 + (p.y / h) * 0.4);
    var n = 0.0;
    for (var i = 0; i < 4; i++) {
      n += rnd.nextDouble() - 0.5;
    }
    n *= noise * 1.7;
    p
      ..r = (p.r * shade + n).clamp(0, 255)
      ..g = (p.g * shade + n).clamp(0, 255)
      ..b = (p.b * shade + n).clamp(0, 255);
  }
  return out;
}

// ------------------------------------------------------------------ content

String _digits(math.Random r, int n) =>
    List.generate(n, (_) => r.nextInt(10)).join();

/// The test sheet: payment codes in several type sizes, Greek and English.
SheetSpec paymentSheet(int seed, {double tilt = 0, double noise = 0}) {
  final r = math.Random(seed);
  final rf = 'RF${_digits(r, 2)}${_digits(r, 19)}';
  final iban = 'GR${_digits(r, 25)}';
  final invoice = '2026-${_digits(r, 5)}';
  final amount = '${100 + r.nextInt(900)},${_digits(r, 2)}';
  return SheetSpec(
    'sheet$seed',
    [
      SheetLine('ΛΟΓΑΡΙΑΣΜΟΣ ΠΑΡΟΧΗΣ Νο $invoice', 44),
      SheetLine('ΚΩΔΙΚΟΣ ΠΛΗΡΩΜΗΣ: $rf', 36),
      SheetLine('IBAN: $iban', 36),
      SheetLine('Ποσό πληρωμής: $amount EUR  Λήξη: 15/11/2026', 30),
      SheetLine(
        'Payment reference: INV-${_digits(r, 8)}-ABC / Customer ${_digits(r, 8)}',
        30,
      ),
      SheetLine(
        'Επωνυμία: Παράδειγμα Ηλεκτρική ΑΕ, Οδός Δοκιμής 15, Αθήνα',
        26,
      ),
      SheetLine(
        'Αριθμός μετρητή ${_digits(r, 9)} · Κατανάλωση 245 kWh · info@example.com',
        22,
      ),
      SheetLine('ΚΩΔΙΚΟΣ ΠΛΗΡΩΜΗΣ (μικρά γράμματα): $rf', 24),
      SheetLine('ΣΥΝΟΛΟ $amount', 54),
    ],
    tiltDegrees: tilt,
    noise: noise,
  );
}

/// A shop receipt of 28 short lines.
SheetSpec receiptSheet({double noise = 6}) {
  final r = math.Random(11);
  final lines = <SheetLine>[
    const SheetLine('ΕΤΑΙΡΕΙΑ ΠΑΡΑΔΕΙΓΜΑ ΑΕ', 40),
    const SheetLine('Οδός Δοκιμής 15, Αθήνα  ΑΦΜ 123456789', 28),
  ];
  const items = [
    'Γάλα φρέσκο 1 λίτρο',
    'Ψωμί ολικής άλεσης',
    'Ελαιόλαδο extra virgin',
    'Ντομάτες εγχώριες',
    'Τυρί φέτα ΠΟΠ',
    'Coffee beans 500 g',
    'Mineral water 6 x 1.5 L',
    'Σαπούνι υγρό',
  ];
  for (var i = 0; i < 20; i++) {
    lines.add(
      SheetLine(
        '${items[i % items.length]}   ${r.nextInt(9) + 1},${_digits(r, 2)}',
        28,
      ),
    );
  }
  lines.add(const SheetLine('ΣΥΝΟΛΟ 45,90 EUR', 40));
  lines.add(const SheetLine('Ευχαριστούμε για την προτίμηση', 28));
  return SheetSpec('receipt', lines, noise: noise);
}

/// A dense printed page: 44 lines of about 85 characters.
SheetSpec densePage({double noise = 5}) {
  const words = [
    'λογαριασμός',
    'κατανάλωση',
    'ρεύματος',
    'περίοδος',
    'χρέωση',
    'ποσό',
    'invoice',
    'payment',
    'customer',
    'service',
    'period',
    'amount',
    'πληρωμή',
    'διεύθυνση',
    'αριθμός',
    'παροχής',
    'contract',
    'meter',
  ];
  final r = math.Random(3);
  final lines = <SheetLine>[];
  for (var i = 0; i < 44; i++) {
    final b = StringBuffer();
    while (b.length < 82) {
      b.write('${words[r.nextInt(words.length)]} ');
    }
    lines.add(SheetLine(b.toString().trim(), 25));
  }
  return SheetSpec('dense', lines, noise: noise);
}
