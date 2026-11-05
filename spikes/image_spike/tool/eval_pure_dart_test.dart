// Runs the A3 (pure Dart) detector on the synthetic dataset on the PC and
// writes build/eval/a3_pc_report.md and a3_pc.csv.
//
//   flutter test tool/eval_pure_dart_test.dart
//
// Run tool/generate_dataset_test.dart first. Optional environment variable
// FACTOR (for example 0.5) scales the pictures, to match the emulator run.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_spike/src/detect/pure_dart_detector.dart';
import 'package:image_spike/src/eval/evaluation.dart';

void main() {
  test('A3 on the synthetic dataset', () {
    final factor = double.tryParse(Platform.environment['FACTOR'] ?? '') ?? 1;
    final manifest = (jsonDecode(
      File('build/synth/manifest.json').readAsStringSync(),
    ) as List).cast<Map<String, Object?>>();
    final images = [
      for (final e in manifest)
        evalImageFrom(
          e,
          File('build/synth/${e['id']}.jpg').readAsBytesSync(),
          factor: factor,
        ),
    ];
    final lines = <String>[csvHeader()];
    final results = runEvaluation(
      [
        PureDartDetector(),
        PureDartDetector(
          areaLow: 0.01,
          areaHigh: 0.04,
          minBrightFraction: 0.008,
          label: 'A3 small-area',
        ),
      ],
      images,
      onResult: (d, id, r) => lines.add(csvLine(r)),
    );
    final tag = factor == 1 ? 'a3_pc' : 'a3_pc_x$factor';
    Directory('build/eval').createSync(recursive: true);
    File('build/eval/$tag.csv').writeAsStringSync('${lines.join('\n')}\n');
    final report = formatReport(results);
    File('build/eval/${tag}_report.md').writeAsStringSync(report);
    // ignore: avoid_print
    print(report);
    expect(results.length, images.length);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
