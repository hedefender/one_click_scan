import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../engines/mlkit_engine.dart';
import '../engines/ocr_engine.dart';
import '../engines/paddle/paddle_config.dart';
import '../engines/paddle_engine.dart';
import '../engines/tesseract_engine.dart';
import 'render.dart';
import 'synthetic_docs.dart';
import 'text_metrics.dart';

/// One engine configuration of the benchmark. [build] gets the document
/// language (`el`, `es`, `ru`).
class EngineConfig {
  const EngineConfig(this.id, this.build);
  final String id;
  final SpikeOcrEngine Function(String lang) build;
}

String _tess(String lang) => switch (lang) {
  'es' => 'spa+eng',
  'ru' => 'rus+eng',
  _ => 'ell+eng',
};

String _paddle(String lang) => switch (lang) {
  'es' => 'latin',
  'ru' => 'eslav',
  _ => 'greek',
};

/// Paddle recognition model for a document language (`el`, `es`, `ru`).
String paddleKeyFor(String lang) => _paddle(lang);

final List<EngineConfig> engineConfigs = [
  EngineConfig('mlkit', (_) => MlKitEngine()),
  EngineConfig(
    'tesseract_fast',
    (l) => TesseractEngine('fast', language: _tess(l)),
  ),
  EngineConfig(
    'tesseract_best',
    (l) => TesseractEngine('best', language: _tess(l)),
  ),
  EngineConfig('paddle', (l) => PaddleEngine(_paddle(l))),
];

/// Orientation experiment: the same Paddle pipeline with the EXIF tag baked
/// into the pixels first.
final List<EngineConfig> exifConfigs = [
  EngineConfig('mlkit', (_) => MlKitEngine()),
  EngineConfig(
    'tesseract_fast',
    (l) => TesseractEngine('fast', language: _tess(l)),
  ),
  EngineConfig(
    'paddle_exifbaked',
    (l) => PaddleEngine(_paddle(l), applyExif: true),
  ),
  EngineConfig('paddle', (l) => PaddleEngine(_paddle(l))),
];

/// Tuning experiment: Tesseract with a single-block page mode (rows stay
/// together) and PaddleOCR with a larger detection size.
final List<EngineConfig> tuningConfigs = [
  EngineConfig(
    'tesseract_fast_psm6',
    (l) => TesseractEngine('fast', language: _tess(l), psm: 6),
  ),
  EngineConfig(
    'tesseract_best_psm6',
    (l) => TesseractEngine('best', language: _tess(l), psm: 6),
  ),
  EngineConfig(
    'paddle_det1280',
    (l) => PaddleEngine(_paddle(l), config: const PaddleConfig(detSide: 1280)),
  ),
];

class BenchRecord {
  BenchRecord({
    required this.engine,
    required this.doc,
    required this.type,
    required this.lang,
    required this.condition,
    required this.ms,
    required this.chars,
    required this.score,
    required this.keys,
    required this.keysFolded,
    required this.muGreek,
    required this.muMicro,
    required this.lines,
    required this.confidence,
    required this.error,
    required this.breakdown,
  });

  final String engine, doc, type, lang, condition;
  final int ms, chars, lines, muGreek, muMicro;
  final TextScore score;
  final Map<String, bool> keys, keysFolded;
  final double? confidence;
  final String? error;
  final Map<String, int> breakdown;

  Map<String, dynamic> toJson() => {
    'engine': engine,
    'doc': doc,
    'type': type,
    'lang': lang,
    'cond': condition,
    'ms': ms,
    'chars': chars,
    'lines': lines,
    'cer': score.cer,
    'scer': score.sortedCer,
    'wer': score.wer,
    'bag': score.bagRecall,
    'charErr': score.charErrors,
    'charTot': score.charTotal,
    'wordErr': score.wordErrors,
    'wordTot': score.wordTotal,
    'keys': keys,
    'keysF': keysFolded,
    'cats': {
      for (final e in score.categories.entries) e.key: [e.value.$1, e.value.$2],
    },
    'muGreek': muGreek,
    'muMicro': muMicro,
    'conf': confidence,
    'error': error,
  };
}

class PerEngineSummary {
  PerEngineSummary(this.engine);
  final String engine;
  int count = 0, ms = 0, keysFound = 0, keysTotal = 0, errors = 0;
  double cerSum = 0, werSum = 0, bagSum = 0;

  void add(BenchRecord r) {
    count++;
    ms += r.ms;
    cerSum += r.score.cer;
    werSum += r.score.wer;
    bagSum += r.score.bagRecall;
    keysTotal += r.keys.length;
    keysFound += r.keys.values.where((v) => v).length;
    if (r.error != null) errors++;
  }

  String get line =>
      '$engine: n=$count  CER ${(100 * cerSum / count).toStringAsFixed(1)}%  '
      'WER ${(100 * werSum / count).toStringAsFixed(1)}%  '
      'bag ${(100 * bagSum / count).toStringAsFixed(1)}%  '
      'keys $keysFound/$keysTotal  ${(ms / count).round()} ms/img  total ${(ms / 1000).toStringAsFixed(0)} s'
      '${errors > 0 ? '  errors $errors' : ''}';
}

const _dump = bool.fromEnvironment('DUMP');

typedef Progress = void Function(String message);

/// Renders all synthetic images into the cache and returns
/// (doc, condition) -> file.
Future<Map<(DocSpec, Condition), File>> prepareImages(
  List<Condition> conditions,
  Progress progress,
) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/bench');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  final files = <(DocSpec, Condition), File>{};
  var seed = 1;
  for (final spec in syntheticDocs) {
    final clean = await renderDoc(spec);
    for (final cond in conditions) {
      progress('render ${spec.id} ${cond.label}');
      final bytes = applyCondition(clean, cond, seed++);
      files[(spec, cond)] = await writeJpeg(
        dir,
        '${spec.id}__${cond.label}',
        bytes,
      );
    }
  }
  return files;
}

/// Runs every engine on every image. Each record is also printed as one
/// `OCRBENCH {json}` line (synthetic data only: safe to log).
Future<List<BenchRecord>> runSynthetic({
  required List<Condition> conditions,
  required List<EngineConfig> engines,
  required Progress progress,
  bool emit = true,
}) async {
  final files = await prepareImages(conditions, progress);
  final records = <BenchRecord>[];
  for (final config in engines) {
    for (final lang in ['el', 'es', 'ru']) {
      final engine = config.build(lang);
      await engine.prepare();
      for (final spec in syntheticDocs.where((d) => d.lang == lang)) {
        for (final cond in conditions) {
          progress('${config.id} ${spec.id} ${cond.label}');
          final result = await engine.recognize(files[(spec, cond)]!.path);
          final record = toRecord(config.id, spec, cond.label, result);
          records.add(record);
          // ignore: avoid_print
          if (emit) print('OCRBENCH ${jsonEncode(record.toJson())}');
          if (emit && _dump) {
            final text = result.text.replaceAll('\n', ' ⏎ ');
            // ignore: avoid_print
            print('OCRTEXT ${config.id}|${spec.id}|${cond.label}|$text');
          }
        }
      }
      await engine.dispose();
    }
    // One config's sessions are not needed by the next one.
    await PaddleEngine.releaseAll();
  }
  // ignore: avoid_print
  if (emit) print('OCRBENCH_DONE ${records.length}');
  return records;
}

BenchRecord toRecord(
  String engine,
  DocSpec spec,
  String cond,
  OcrResult result,
) {
  final (greek, micro) = muCounts(result.text);
  return BenchRecord(
    engine: engine,
    doc: spec.id,
    type: spec.type,
    lang: spec.lang,
    condition: cond,
    ms: result.elapsedMs,
    chars: result.text.length,
    score: score(spec.groundTruth, result.text),
    keys: {
      for (final e in spec.keys.entries)
        e.key: containsValue(result.text, e.value),
    },
    keysFolded: {
      for (final e in spec.keys.entries)
        e.key: containsFolded(result.text, e.value),
    },
    muGreek: greek,
    muMicro: micro,
    lines: result.lines.length,
    confidence: result.confidence,
    error: result.error,
    breakdown: result.breakdown,
  );
}

Map<String, PerEngineSummary> summarize(List<BenchRecord> records) {
  final out = <String, PerEngineSummary>{};
  for (final r in records) {
    out.putIfAbsent(r.engine, () => PerEngineSummary(r.engine)).add(r);
  }
  return out;
}
