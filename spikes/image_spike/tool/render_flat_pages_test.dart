// Draws the flat invented pages (assets/synth/pages/<name>.png and .txt).
//
//   flutter test tool/render_flat_pages_test.dart
//
// It is a test only because dart:ui needs the Flutter engine; it asserts that
// the files were written. The text of each page is in `documents.dart`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_spike/src/synth/documents.dart';

Future<img.Image> render(SynthDocument d) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, d.width.toDouble(), d.height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFF7F5EE),
  );
  final margin = d.fontSize * 1.2;
  final lineHeight = (d.height - 2 * margin) / d.lines.length;
  for (var i = 0; i < d.lines.length; i++) {
    final heading = i == 0;
    final painter = TextPainter(
      text: TextSpan(
        text: d.lines[i],
        style: TextStyle(
          color: const ui.Color(0xFF111111),
          fontSize: heading ? d.fontSize * 1.15 : d.fontSize,
          fontFamily: 'NotoSans',
          fontWeight: heading ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: d.width - 2 * margin);
    final pair = d.pairs != null && i >= 1 ? d.pairs![i - 1] : null;
    if (pair == null) {
      painter.paint(canvas, ui.Offset(margin, margin + i * lineHeight));
      continue;
    }
    // Two columns: the label at the left, the value at the right margin.
    TextPainter column(String text) => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const ui.Color(0xFF111111),
          fontSize: d.fontSize,
          fontFamily: 'NotoSans',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final label = column(pair.$1);
    final value = column(pair.$2);
    label.paint(canvas, ui.Offset(margin, margin + i * lineHeight));
    value.paint(
      canvas,
      ui.Offset(d.width - margin - value.width, margin + i * lineHeight),
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(d.width, d.height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return img.Image.fromBytes(
    width: d.width,
    height: d.height,
    bytes: data!.buffer,
    numChannels: 4,
  ).convert(numChannels: 3);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('render the flat pages', (tester) async {
    await tester.runAsync(() async {
      final loader = FontLoader('NotoSans')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync(),
            ),
          ),
        );
      await loader.load();
      Directory('assets/synth/pages').createSync(recursive: true);
      for (final d in allDocuments) {
        final image = await render(d);
        File('assets/synth/pages/${d.name}.png')
            .writeAsBytesSync(img.encodePng(image));
        File('assets/synth/pages/${d.name}.txt')
            .writeAsStringSync('${d.lines.join('\n')}\n');
        expect(
          File('assets/synth/pages/${d.name}.png').lengthSync(),
          greaterThan(1000),
        );
      }
    });
  });
}
