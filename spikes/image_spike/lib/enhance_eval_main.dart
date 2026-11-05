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
import 'src/eval/evaluation.dart';
import 'src/eval/ocr_eval.dart';
import 'src/eval/text_metrics.dart';
import 'src/image/enhance.dart';
import 'src/image/rectify.dart';
import 'src/synth/documents.dart';

/// Entry point of the contrast and shadow evaluation (ENTRY=lib/enhance_eval_main.dart
/// MARK=ENHEVAL): every page that lies whole in the frame is straightened with
/// the true outline (so the detection does not matter here) and read with the
/// real OCR engine after each option of `enhancers`. Prints ENHEVAL csv lines:
/// numbers only, never the text.
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
      final file = File('${cache.path}/enh_eval_${counter++}.jpg')
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
        return OcrRun(
          lines: outcome is OcrSuccess
              ? [
                  for (final l in outcome.result.lines)
                    if (!l.filtered) l.text,
                ]
              : const [],
          wallMs: ms,
        );
      } finally {
        file.deleteSync();
      }
    }

    // Warm up.
    final first = await loadImage(
      manifest.indexWhere((e) => e['truth'] != null),
    );
    for (final pack in ['greek', 'latin']) {
      await ocr(first.frame, pack);
    }
    _line('ENHEVAL info warm-up done');
    _line(
      'ENHEVAL header id,category,option,enhanceMs,ocrMs,cer,wordRecall,keyRecall',
    );

    var done = 0;
    for (var i = 0; i < manifest.length; i++) {
      final image = await loadImage(i);
      if (!image.hasDocument || image.partial || image.fillsFrame) continue;
      final doc = documentByName(image.document!);
      final pack = packFor(doc);
      final known = doc.lines.join('\n');
      final crop = warpToQuadDart(
        image.frame,
        image.truth!,
        focalPx: image.focalPx,
      );
      for (final e in enhancers.entries) {
        final sw = Stopwatch()..start();
        final frame = e.value(crop);
        final enhanceMs = sw.elapsedMilliseconds;
        final run = await ocr(frame, pack);
        _line(
          'ENHEVAL csv ${image.id},${image.category},${e.key},$enhanceMs,${run.wallMs},'
          '${characterErrorRate(run.text, known).toStringAsFixed(4)},'
          '${wordRecall(run.text, known).toStringAsFixed(4)},'
          '${keyTokenRecall(run.text, doc.keyTokens).toStringAsFixed(4)}',
        );
      }
      _line('ENHEVAL progress ${++done}');
    }
    await engine.dispose();
    _line(
      'ENHEVAL rss max ${(ProcessInfo.maxRss / 1e6).toStringAsFixed(0)} MB',
    );
    _line('ENHEVAL done $done pages');
  } catch (error, stack) {
    _line('ENHEVAL FAILED ${error.runtimeType}: $error');
    _line('ENHEVAL stack ${stack.toString().split('\n').take(6).join(' | ')}');
  }
}

void _line(String s) {
  // ignore: avoid_print
  print(s);
}
