// Writes the synthetic photos and their ground truth to build/synth/.
//
//   flutter test tool/generate_dataset_test.dart
//
// Output: build/synth/<id>.jpg, build/synth/manifest.json (spec, true outline,
// flags, known text) and build/synth/contact_sheet.jpg (a thumbnail grid for
// a quick look). Pure Dart; runs in a test only so it fits the project tools.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_spike/src/synth/dataset.dart';
import 'package:image_spike/src/synth/documents.dart';
import 'package:image_spike/src/synth/scene.dart';

void main() {
  test('generate the dataset', () {
    final out = Directory('build/synth')..createSync(recursive: true);
    final pages = {
      for (final d in allDocuments)
        d.name: FlatPage.fromImage(
          img.decodePng(
            File('assets/synth/pages/${d.name}.png').readAsBytesSync(),
          )!,
        ),
    };
    final specs = buildDataset();
    final manifest = <Map<String, Object?>>[];
    final thumbs = <img.Image>[];
    final sw = Stopwatch()..start();
    for (final s in specs) {
      final r = renderScene(s, pages[s.document]!);
      File('${out.path}/${s.id}.jpg')
          .writeAsBytesSync(img.encodeJpg(r.image, quality: 92));
      final doc = documentByName(s.document);
      manifest.add({
        ...s.toJson(),
        'truth': r.truth?.toJson(),
        'partial': r.partial,
        'fillsFrame': r.fillsFrame,
        'focalPx': double.parse(r.focalPx.toStringAsFixed(1)),
        'lines': doc.lines,
        'keyTokens': doc.keyTokens,
      });
      thumbs.add(img.copyResize(r.image, width: 192));
    }
    File('${out.path}/manifest.json')
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(manifest));

    const cols = 11;
    final rows = (thumbs.length / cols).ceil();
    final cellH = thumbs.first.height;
    final sheet = img.Image(width: cols * 192, height: rows * cellH);
    img.fill(sheet, color: img.ColorRgb8(30, 30, 30));
    for (var i = 0; i < thumbs.length; i++) {
      img.compositeImage(
        sheet,
        thumbs[i],
        dstX: (i % cols) * 192,
        dstY: (i ~/ cols) * cellH,
      );
    }
    File('${out.path}/contact_sheet.jpg')
        .writeAsBytesSync(img.encodeJpg(sheet, quality: 85));
    // ignore: avoid_print
    print('GENERATED ${specs.length} scenes in ${sw.elapsedMilliseconds} ms');
    expect(File('${out.path}/manifest.json').existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 15)));
}
