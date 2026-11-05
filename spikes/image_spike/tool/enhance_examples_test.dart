import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_spike/src/eval/evaluation.dart';
import 'package:image_spike/src/image/enhance.dart';
import 'package:image_spike/src/image/rectify.dart';

/// Writes before/after strips (one picture per option, side by side) of a few
/// hard scenes into docs/image_spike_data/enhance_examples/.
///   flutter test tool/enhance_examples_test.dart
void main() {
  test('write before/after strips', () {
    final manifest = (jsonDecode(
      File('assets/eval_full/manifest.json').readAsStringSync(),
    ) as List).cast<Map<String, Object?>>();
    final wanted = {'light', 'low_contrast', 'combined', 'crumple'};
    final seen = <String, int>{};
    final out = Directory('../../docs/image_spike_data/enhance_examples')
      ..createSync(recursive: true);
    for (final e in manifest) {
      final cat = e['category']! as String;
      if (!wanted.contains(cat) || e['truth'] == null) continue;
      if (e['partial'] == true || e['fillsFrame'] == true) continue;
      if ((seen[cat] ?? 0) >= 2) continue;
      seen[cat] = (seen[cat] ?? 0) + 1;
      final image = evalImageFrom(
        e,
        File('assets/eval_full/${e['id']}.jpg').readAsBytesSync(),
      );
      final crop = warpToQuadDart(
        image.frame,
        image.truth!,
        focalPx: image.focalPx,
      );
      const cellH = 560;
      final cells = <img.Image>[];
      for (final en in enhancers.entries) {
        final f = en.value(crop);
        final im = img.Image.fromBytes(
          width: f.width,
          height: f.height,
          bytes: f.rgb.buffer,
          numChannels: 3,
        );
        cells.add(
          img.copyResize(
            im,
            height: cellH,
            interpolation: img.Interpolation.average,
          ),
        );
      }
      final total = cells.fold<int>(0, (s, c) => s + c.width + 6);
      final strip = img.Image(width: total, height: cellH);
      img.fill(strip, color: img.ColorRgb8(255, 0, 255));
      var x = 0;
      for (final c in cells) {
        img.compositeImage(strip, c, dstX: x);
        x += c.width + 6;
      }
      File('${out.path}/${e['id']}.jpg')
          .writeAsBytesSync(img.encodeJpg(strip, quality: 80));
    }
    expect(out.listSync(), isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
