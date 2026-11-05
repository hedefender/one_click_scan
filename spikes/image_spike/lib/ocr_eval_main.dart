import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'ocr_copy/core/logging/app_logger.dart';
import 'ocr_copy/domain/entities/ocr_outcome.dart';
import 'ocr_copy/domain/entities/upright_image.dart';
import 'ocr_copy/domain/ocr/ocr_language_pack_registry.dart';
import 'ocr_copy/services/ocr/ocr_model_store.dart';
import 'ocr_copy/services/ocr/paddle_ocr_engine.dart';
import 'src/detect/detection.dart';
import 'src/detect/opencv_detector.dart';
import 'src/detect/pure_dart_detector.dart';
import 'src/eval/evaluation.dart';
import 'src/eval/ocr_eval.dart';
import 'src/geometry/quad.dart';
import 'src/image/opencv_rectify.dart';
import 'src/image/rectify.dart';

/// Entry point of the OCR-gain evaluation (tool/run_eval_on_device.sh with
/// ENTRY=lib/ocr_eval_main.dart MARK=OCREVAL): a release APK that reads every
/// synthetic page with the real OCR engine of the app (a copy, see
/// tool/sync_ocr_code.sh) as the whole frame, as the perfect crop and as the
/// crop of each pipeline, and prints OCREVAL lines to logcat: numbers only,
/// never the text. Nothing is stored or sent.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  try {
    final manifest = (jsonDecode(
      await rootBundle.loadString('assets/eval_full/manifest.json'),
    ) as List).cast<Map<String, Object?>>();
    Future<EvalImage> loadImage(int i) async {
      final e = manifest[i];
      final data = await rootBundle.load('assets/eval_full/${e['id']}.jpg');
      return evalImageFrom(
        e,
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    }

    final first = await loadImage(0);
    _line(
      'OCREVAL info ${manifest.length} pictures, ${first.width}x${first.height}',
    );

    // Detection at full size (the half-size table is in the other run).
    final detectors = <DocumentDetector>[
      PureDartDetector(),
      OpenCvDetector(),
      OpenCvDetector(approxPolyDp: false),
    ];
    final detResults = await runEvaluationLazy(
      detectors,
      count: manifest.length,
      loadImage: loadImage,
      onResult: (d, id, r) => _line('OCREVAL det $d $id'),
    );
    for (final l in formatReport(detResults).split('\n')) {
      _line('OCREVAL detreport $l');
    }

    final cache = await getTemporaryDirectory();
    final support = await getApplicationSupportDirectory();
    final registry = OcrLanguagePackRegistry.standard;
    final engine = PaddleOcrEngine(
      registry: registry,
      logger: const DebugAppLogger(),
      models: OcrModelStore(
        directory: Directory('${support.path}/ocr_models'),
        loadAsset: rootBundle.load,
        registry: registry,
      ),
    );

    var counter = 0;
    Future<OcrRun> ocr(RgbFrame f, String pack) async {
      final image = img.Image.fromBytes(
        width: f.width,
        height: f.height,
        bytes: f.rgb.buffer,
        numChannels: 3,
      );
      final file = File('${cache.path}/ocr_eval_${counter++}.jpg')
        ..writeAsBytesSync(img.encodeJpg(image, quality: 95));
      try {
        final sw = Stopwatch()..start();
        final outcome = await engine.recognize(
          UprightImage(
            path: file.path,
            width: f.width,
            height: f.height,
            sourceWidth: f.width,
            sourceHeight: f.height,
          ),
          packId: pack,
          timeout: const Duration(seconds: 120),
        );
        final ms = sw.elapsedMilliseconds;
        if (outcome is OcrSuccess) {
          return OcrRun(
            lines: [
              for (final l in outcome.result.lines)
                if (!l.filtered) l.text,
            ],
            wallMs: ms,
          );
        }
        _line('OCREVAL warn outcome ${outcome.runtimeType}');
        return OcrRun(lines: const [], wallMs: ms);
      } finally {
        file.deleteSync();
      }
    }

    // Warm up both packs so model loading is not in any timing.
    for (final pack in ['greek', 'latin']) {
      await ocr(
        (await loadImage(manifest.indexWhere((e) => e['truth'] != null))).frame,
        pack,
      );
    }
    _line('OCREVAL info warm-up done');

    final total = manifest.where((e) => e['truth'] != null).length;
    var done = 0;
    final rows = await evaluateOcrGain(
      count: manifest.length,
      loadImage: loadImage,
      pipelines: [
        Pipeline('A3', PureDartDetector(), warpToQuadDart2),
        Pipeline(
          'A3small',
          PureDartDetector(
            areaLow: 0.01,
            areaHigh: 0.04,
            minBrightFraction: 0.008,
            label: 'A3 small-area',
          ),
          warpToQuadDart2,
        ),
        Pipeline('A1', OpenCvDetector(approxPolyDp: false), warpToQuadOpenCv2),
        Pipeline('A1poly', OpenCvDetector(), warpToQuadOpenCv2),
      ],
      oracleWarp: warpToQuadDart2,
      ocr: ocr,
      onRow: (r) {
        _line('OCREVAL csv ${r.csv()}');
        if (r.condition == 'frame') {
          done++;
          _line('OCREVAL progress $done/$total');
        }
      },
    );
    await engine.dispose();
    for (final l in formatOcrReport(rows).split('\n')) {
      _line('OCREVAL report $l');
    }
    _line(
      'OCREVAL rss max ${(ProcessInfo.maxRss / 1e6).toStringAsFixed(0)} MB',
    );
    _line('OCREVAL done ${rows.length} rows');
  } catch (error, stack) {
    _line('OCREVAL FAILED ${error.runtimeType}: $error');
    _line('OCREVAL stack ${stack.toString().split('\n').take(6).join(' | ')}');
  }
}

RgbFrame warpToQuadDart2(RgbFrame f, Quad quad, double focalPx) =>
    warpToQuadDart(f, quad, focalPx: focalPx);

RgbFrame warpToQuadOpenCv2(RgbFrame f, Quad quad, double focalPx) =>
    warpToQuadOpenCv(f, quad, focalPx: focalPx);

void _line(String s) {
  // ignore: avoid_print
  print(s);
}
