import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'src/detect/opencv_detector.dart';
import 'src/detect/pure_dart_detector.dart';
import 'src/eval/evaluation.dart';

/// Entry point of the detector evaluation (tool/run_eval_on_device.sh): a
/// release APK that loads the half-size synthetic dataset from the assets,
/// runs A3 (pure Dart) and A1 (OpenCV) on every picture and prints, to logcat,
/// IMGEVAL lines: one CSV line per picture and detector, the Markdown report,
/// and `IMGEVAL done`. Nothing is stored or sent.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  try {
    final manifest = (jsonDecode(
      await rootBundle.loadString('assets/eval/manifest.json'),
    ) as List).cast<Map<String, Object?>>();
    final images = <EvalImage>[];
    for (final e in manifest) {
      final data = await rootBundle.load('assets/eval/${e['id']}.jpg');
      images.add(
        evalImageFrom(
          e,
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        ),
      );
    }
    _line('IMGEVAL csv ${csvHeader()}');
    final results = runEvaluation(
      [
        PureDartDetector(),
        OpenCvDetector(),
        OpenCvDetector(approxPolyDp: false),
      ],
      images,
      onResult: (d, id, r) => _line('IMGEVAL csv ${csvLine(r)}'),
    );
    for (final l in formatReport(results).split('\n')) {
      _line('IMGEVAL report $l');
    }
    _line('IMGEVAL done ${results.length} results');
  } catch (error, stack) {
    _line('IMGEVAL FAILED ${error.runtimeType}: $error');
    _line('IMGEVAL stack ${stack.toString().split('\n').take(6).join(' | ')}');
  }
}

void _line(String s) {
  // ignore: avoid_print
  print(s);
}
