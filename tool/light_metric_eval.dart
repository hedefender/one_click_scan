// Evaluation of the light metric on the synthetic scenes (Phase 6.2, ADR-030).
//
//   dart run tool/light_metric_eval.dart
//
// Renders the receipt scenes of the unit tests (table and dark background,
// tilted) with the light scaled down like a lower exposure, plus a faint
// "thermal" receipt, takes the metric from a 160 px copy (what the after-shot
// check does) and prints the table that is copied to the docs. Invented
// documents only; no file is written.
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:one_click_scan/domain/lighting/lighting_config.dart';
import 'package:one_click_scan/services/imaging/light_jobs.dart';

import '../test/support/synth/scene.dart';

FlatPage page({
  required int paper,
  required int ink,
  int w = 300,
  int h = 420,
}) {
  final rgb = Uint8List(w * h * 3)..fillRange(0, w * h * 3, paper);
  for (var row = 0; row < 12; row++) {
    for (var y = 40 + row * 28; y < 52 + row * 28; y++) {
      for (var x = 30; x < 270; x++) {
        final o = (y * w + x) * 3;
        rgb[o] = rgb[o + 1] = rgb[o + 2] = ink;
      }
    }
  }
  return FlatPage(w, h, rgb);
}

SceneSpec spec(String id, Background background, {double contrast = 1.0}) =>
    SceneSpec(
      id: id,
      category: id,
      document: 'x',
      seed: 7,
      tiltXDeg: 8,
      tiltYDeg: 12,
      rollDeg: 4,
      background: background,
      contrast: contrast,
    );

img.Image scaled(img.Image image, double factor) {
  final out = img.Image.from(image);
  for (final p in out) {
    p
      ..r = (p.r * factor).round().clamp(0, 255)
      ..g = (p.g * factor).round().clamp(0, 255)
      ..b = (p.b * factor).round().clamp(0, 255);
  }
  return out;
}

void main() {
  final threshold = LightingConfig.minPaperLevel;
  final cases = <String, img.Image>{
    'receipt on a table': renderScene(
      spec('table', Background.table),
      page(paper: 238, ink: 25),
    ).image,
    'receipt on a dark background': renderScene(
      spec('dark', Background.dark),
      page(paper: 238, ink: 25),
    ).image,
    'faint thermal receipt on a table': renderScene(
      spec('thermal', Background.table, contrast: 0.45),
      page(paper: 225, ink: 190),
    ).image,
  };
  final factors = [1.0, 0.7, 0.5, 0.4, 0.3, 0.2, 0.12];

  // ignore: avoid_print
  print('threshold (paper level below it = low light): $threshold');
  // ignore: avoid_print
  print('| scene | light | paper | contrast | low light |');
  // ignore: avoid_print
  print('|---|---|---|---|---|');
  for (final entry in cases.entries) {
    for (final f in factors) {
      final small = img.copyResize(
        scaled(entry.value, f),
        width: LightingConfig.thumbnailSide,
        interpolation: img.Interpolation.average,
      );
      final m = metricOfImage(small)!;
      final low = LightingConfig.isLowLight(m);
      // ignore: avoid_print
      print(
        '| ${entry.key} | ${(f * 100).round()}% | '
        '${m.paper.toStringAsFixed(1)} | ${m.contrast.toStringAsFixed(1)} | '
        '${low ? 'YES' : 'no'} |',
      );
    }
  }
}
