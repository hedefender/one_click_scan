// Writes the dataset as bundled assets at half size: assets/eval/<id>.jpg and
// assets/eval/manifest.json (truth outlines scaled with the pictures).
//
//   flutter test tool/export_eval_assets_test.dart
//
// Run tool/generate_dataset_test.dart first. Half size (768 x 1024) keeps the
// bundle small; the detectors work on a 640 px picture anyway.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('export half-size evaluation assets', () {
    const factor = 0.5;
    final manifest = (jsonDecode(
      File('build/synth/manifest.json').readAsStringSync(),
    ) as List).cast<Map<String, Object?>>();
    Directory('assets/eval').createSync(recursive: true);
    final out = <Map<String, Object?>>[];
    for (final e in manifest) {
      final image = img.decodeJpg(
        File('build/synth/${e['id']}.jpg').readAsBytesSync(),
      )!;
      final small = img.copyResize(
        image,
        width: (image.width * factor).round(),
        height: (image.height * factor).round(),
        interpolation: img.Interpolation.average,
      );
      File('assets/eval/${e['id']}.jpg')
          .writeAsBytesSync(img.encodeJpg(small, quality: 90));
      final truth = e['truth'];
      out.add({
        'id': e['id'],
        'category': e['category'],
        'document': e['document'],
        'partial': e['partial'],
        'fillsFrame': e['fillsFrame'],
        'focalPx': (e['focalPx'] as num) * factor,
        'truth': truth == null
            ? null
            : {
                'points': [
                  for (final p in ((truth as Map)['points'] as List))
                    [(p[0] as num) * factor, (p[1] as num) * factor],
                ],
              },
      });
    }
    // The OCR evaluation reads the pictures at full size (1536 x 2048): dense
    // pages are not readable at half size. Not in git (regenerated).
    Directory('assets/eval_full').createSync(recursive: true);
    for (final e in manifest) {
      File('build/synth/${e['id']}.jpg')
          .copySync('assets/eval_full/${e['id']}.jpg');
    }
    File('assets/eval_full/manifest.json').writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert([
        for (final e in manifest)
          {
            'id': e['id'],
            'category': e['category'],
            'document': e['document'],
            'partial': e['partial'],
            'fillsFrame': e['fillsFrame'],
            'focalPx': e['focalPx'],
            'truth': e['truth'],
          },
      ]),
    );
    File('assets/eval/manifest.json')
        .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
    expect(out.length, manifest.length);
  });
}
