import '../detect/detection.dart';
import '../geometry/quad.dart';
import '../synth/documents.dart';
import 'evaluation.dart';
import 'text_metrics.dart';

/// What the OCR returned for one picture (the text only ever lives here, in
/// memory, for the comparison; only the numbers are printed).
class OcrRun {
  const OcrRun({required this.lines, required this.wallMs});

  /// The visible (not filtered) lines in the engine's reading order.
  final List<String> lines;
  final int wallMs;

  String get text => lines.join('\n');
  int get wordCount => wordsOf(text).length;
}

typedef OcrFn = Future<OcrRun> Function(RgbFrame frame, String packId);

/// Straightens the page inside [quad]; [focalPx] is the camera's focal length
/// in frame pixels (0 when unknown).
typedef WarpFn = RgbFrame Function(RgbFrame frame, Quad quad, double focalPx);

/// A detector with the warp that goes with it: one candidate pipeline.
class Pipeline {
  const Pipeline(this.name, this.detector, this.warp);

  final String name;
  final DocumentDetector detector;
  final WarpFn warp;
}

class OcrRow {
  OcrRow({
    required this.id,
    required this.category,
    required this.condition,
    required this.used,
    required this.cer,
    required this.wordRecall,
    required this.keyRecall,
    required this.order,
    required this.orderMatched,
    required this.ocrWords,
    required this.ocrMs,
    this.frameCoverage = 1,
    this.pairing = -1,
    this.reusedFrom,
    this.cropWidth = 0,
    this.cropHeight = 0,
    this.detectMs = 0,
    this.warpMs = 0,
    this.score = 0,
  });

  final String id;
  final String category;
  final String condition;

  /// A crop was used (the detection was trusted).
  final bool used;
  final double cer;
  final double wordRecall;
  final double keyRecall;
  final double order;
  final int orderMatched;

  /// Words the OCR returned (any, right or wrong): the input of the safety check.
  final int ocrWords;
  final int ocrMs;

  /// Share of the words the OCR read in the whole frame that it also reads in
  /// this picture (no ground truth needed; 1 for the frame itself). The input
  /// of the content-based safety check.
  final double frameCoverage;

  /// Label-value pairing accuracy on a two-column receipt, or -1 when the page
  /// is not one.
  final double pairing;

  /// The OCR of an earlier, identical crop of the same picture was reused.
  final String? reusedFrom;
  final int cropWidth;
  final int cropHeight;
  final double detectMs;
  final double warpMs;
  final double score;

  static String csvHeader() =>
      'id,category,condition,used,reusedFrom,cropW,cropH,score,detectMs,warpMs,ocrMs,'
      'cer,wordRecall,keyRecall,order,orderMatched,ocrWords,frameCoverage,pairing';

  String csv() => [
    id,
    category,
    condition,
    used,
    reusedFrom ?? '',
    cropWidth,
    cropHeight,
    score.toStringAsFixed(3),
    detectMs.toStringAsFixed(1),
    warpMs.toStringAsFixed(1),
    ocrMs,
    cer.toStringAsFixed(4),
    wordRecall.toStringAsFixed(4),
    keyRecall.toStringAsFixed(4),
    order.toStringAsFixed(3),
    orderMatched,
    ocrWords,
  ].join(',');
}

String packFor(SynthDocument d) => d.name.endsWith('_el') ? 'greek' : 'latin';

OcrRow _measure(
  EvalImage image,
  SynthDocument doc,
  String condition,
  OcrRun run, {
  required bool used,
  String? reusedFrom,
  RgbFrame? crop,
  double detectMs = 0,
  double warpMs = 0,
  double score = 0,
  double frameCoverage = 1,
}) {
  final known = doc.lines.join('\n');
  final order = readingOrder(run.lines, doc.lines);
  return OcrRow(
    id: image.id,
    category: image.category,
    condition: condition,
    used: used,
    reusedFrom: reusedFrom,
    cropWidth: crop?.width ?? 0,
    cropHeight: crop?.height ?? 0,
    detectMs: detectMs,
    warpMs: warpMs,
    score: score,
    cer: characterErrorRate(run.text, known),
    wordRecall: wordRecall(run.text, known),
    keyRecall: keyTokenRecall(run.text, doc.keyTokens),
    order: order.score,
    orderMatched: order.matched,
    ocrWords: run.wordCount,
    ocrMs: run.wallMs,
    frameCoverage: frameCoverage,
    pairing: doc.pairs == null
        ? -1
        : pairingAccuracy(run.text, doc.pairs!).accuracy,
  );
}

OcrRow _copyAs(
  OcrRow r,
  String condition, {
  required bool used,
  String? reusedFrom,
  int cropWidth = 0,
  int cropHeight = 0,
  double detectMs = 0,
  double warpMs = 0,
  double score = 0,
}) {
  return OcrRow(
    id: r.id,
    category: r.category,
    condition: condition,
    used: used,
    reusedFrom: reusedFrom,
    cropWidth: cropWidth,
    cropHeight: cropHeight,
    detectMs: detectMs,
    warpMs: warpMs,
    score: score,
    cer: r.cer,
    wordRecall: r.wordRecall,
    keyRecall: r.keyRecall,
    order: r.order,
    orderMatched: r.orderMatched,
    ocrWords: r.ocrWords,
    ocrMs: r.ocrMs,
    frameCoverage: r.frameCoverage,
    pairing: r.pairing,
  );
}

/// Reads every page with the whole frame (what the app does now), with the
/// perfect crop (the true outline, where the whole page is in the frame) and
/// with the crop of each pipeline when its detection is trusted.
///
/// The pictures come either as a [images] list or, to keep memory low, one at
/// a time from [loadImage] ([count] of them).
Future<List<OcrRow>> evaluateOcrGain({
  List<EvalImage>? images,
  int? count,
  Future<EvalImage> Function(int index)? loadImage,
  required List<Pipeline> pipelines,
  required WarpFn oracleWarp,
  required OcrFn ocr,
  double threshold = 0.5,
  void Function(OcrRow row)? onRow,
}) async {
  final rows = <OcrRow>[];
  void add(OcrRow r) {
    rows.add(r);
    onRow?.call(r);
  }

  final n = images?.length ?? count!;
  for (var index = 0; index < n; index++) {
    final image = images != null ? images[index] : await loadImage!(index);
    if (!image.hasDocument) continue;
    final entry = image.document;
    if (entry == null) continue;
    final doc = documentByName(entry);
    final pack = packFor(doc);

    final frameRun = await ocr(image.frame, pack);
    final frameRow = _measure(image, doc, 'frame', frameRun, used: false);
    add(frameRow);

    if (!image.partial && !image.fillsFrame) {
      final crop = oracleWarp(image.frame, image.truth!, image.focalPx);
      final run = await ocr(crop, pack);
      add(
        _measure(
          image,
          doc,
          'oracle',
          run,
          used: true,
          crop: crop,
          frameCoverage: wordRecall(run.text, frameRun.text),
        ),
      );
    }

    final done = <(Quad, OcrRow)>[];
    for (final p in pipelines) {
      final det = p.detector.detect(image.frame);
      final detectMs = det.microsTotal / 1000;
      final q = det.quad;
      final trusted = q != null && det.score >= threshold;
      if (!trusted) {
        add(
          _copyAs(
            frameRow,
            p.name,
            used: false,
            detectMs: detectMs,
            score: det.score,
          ),
        );
        continue;
      }
      final sw = Stopwatch()..start();
      final crop = p.warp(image.frame, q, image.focalPx);
      final warpMs = sw.elapsedMicroseconds / 1000;
      OcrRow? same;
      for (final (dq, dr) in done) {
        if (quadIou(dq, q) > 0.995) {
          same = dr;
          break;
        }
      }
      if (same != null) {
        add(
          _copyAs(
            same,
            p.name,
            used: true,
            reusedFrom: same.condition,
            cropWidth: crop.width,
            cropHeight: crop.height,
            detectMs: detectMs,
            warpMs: warpMs,
            score: det.score,
          ),
        );
      } else {
        final run = await ocr(crop, pack);
        final row = _measure(
          image,
          doc,
          p.name,
          run,
          used: true,
          crop: crop,
          detectMs: detectMs,
          warpMs: warpMs,
          score: det.score,
          frameCoverage: wordRecall(run.text, frameRun.text),
        );
        done.add((q, row));
        add(row);
      }
    }
  }
  return rows;
}

double _mean(Iterable<double> v) {
  final l = v.toList();
  return l.isEmpty ? double.nan : l.reduce((a, b) => a + b) / l.length;
}

String _f(double v, [int d = 3]) => v.isNaN ? '-' : v.toStringAsFixed(d);

/// The safety check after a crop: if the OCR finds fewer than [ratio] of the
/// words it finds in the whole frame, the frame is used instead.
OcrRow applySafetyCheck(OcrRow frame, OcrRow crop, {double ratio = 0.9}) {
  if (!crop.used) return crop;
  final fewer = crop.ocrWords < ratio * frame.ocrWords;
  return fewer ? _copyAs(frame, '${crop.condition}+check', used: false) : crop;
}

/// The Markdown report of the OCR gain.
String formatOcrReport(List<OcrRow> rows, {double tolerance = 0.02}) {
  final b = StringBuffer();
  final byId = <String, Map<String, OcrRow>>{};
  for (final r in rows) {
    byId.putIfAbsent(r.id, () => {})[r.condition] = r;
  }
  final conditions = rows.map((r) => r.condition).toSet().toList();
  final pipelineNames = conditions
      .where((c) => c != 'frame' && c != 'oracle')
      .toList();

  b.writeln(
    '### Pages read: ${byId.length} (with the whole frame as the baseline)\n',
  );
  final frames = [for (final m in byId.values) m['frame']!];
  b.writeln(
    'Whole frame (today): mean CER ${_f(_mean(frames.map((r) => r.cer)))}, '
    'word recall ${_f(_mean(frames.map((r) => r.wordRecall)))}, '
    'key-token recall ${_f(_mean(frames.map((r) => r.keyRecall)))}, '
    'reading order ${_f(_mean(frames.map((r) => r.order)))}, '
    'OCR time ${_f(_mean(frames.map((r) => r.ocrMs.toDouble())), 0)} ms per page.\n',
  );

  b.writeln(
    '#### Paired change against the whole frame, on the pages where the crop was used\n',
  );
  b.writeln(
    'Negative CER change and positive recall change are improvements. '
    '"Better/worse" counts pages whose CER moved by more than ${(tolerance * 100).toStringAsFixed(0)} points.\n',
  );
  b.writeln(
    '| condition | pages cropped | mean CER frame | mean CER crop | change | word recall change | key-token change | better | worse | reading order frame -> crop | OCR time frame -> crop (ms) |',
  );
  b.writeln('|---|---|---|---|---|---|---|---|---|---|---|');
  for (final c in ['oracle', ...pipelineNames]) {
    final pairs = [
      for (final m in byId.values)
        if (m[c] != null && m[c]!.used) (m['frame']!, m[c]!),
    ];
    if (pairs.isEmpty) continue;
    final dCer = pairs.map((p) => p.$2.cer - p.$1.cer);
    int better(Iterable<double> d) => d.where((x) => x < -tolerance).length;
    int worse(Iterable<double> d) => d.where((x) => x > tolerance).length;
    b.writeln(
      '| $c | ${pairs.length} | ${_f(_mean(pairs.map((p) => p.$1.cer)))} | '
      '${_f(_mean(pairs.map((p) => p.$2.cer)))} | ${_f(_mean(dCer))} | '
      '${_f(_mean(pairs.map((p) => p.$2.wordRecall - p.$1.wordRecall)))} | '
      '${_f(_mean(pairs.map((p) => p.$2.keyRecall - p.$1.keyRecall)))} | '
      '${better(dCer)} | **${worse(dCer)}** | '
      '${_f(_mean(pairs.map((p) => p.$1.order)), 2)} -> ${_f(_mean(pairs.map((p) => p.$2.order)), 2)} | '
      '${_f(_mean(pairs.map((p) => p.$1.ocrMs.toDouble())), 0)} -> ${_f(_mean(pairs.map((p) => p.$2.ocrMs.toDouble())), 0)} |',
    );
  }
  b.writeln();

  for (final c in pipelineNames) {
    final hurt = [
      for (final m in byId.values)
        if (m[c] != null &&
            m[c]!.used &&
            (m[c]!.cer - m['frame']!.cer > tolerance ||
                m['frame']!.wordRecall - m[c]!.wordRecall > tolerance))
          m[c]!,
    ];
    b.writeln(
      'Pages where the crop of **$c** made the reading worse (CER up or word recall down by more than ${(tolerance * 100).toStringAsFixed(0)} points): ${hurt.length}'
      '${hurt.isEmpty ? '' : ' ('
                '${hurt.map((r) => '${r.id}: CER ${_f(byId[r.id]!['frame']!.cer)} -> ${_f(r.cer)}, recall ${_f(byId[r.id]!['frame']!.wordRecall, 2)} -> ${_f(r.wordRecall, 2)}').join('; ')})'}.\n',
    );
  }

  // By category for the first pipeline and the oracle.
  final cats = rows.map((r) => r.category).toSet().toList();
  b.writeln(
    '#### By category (mean CER and word recall: whole frame / ${pipelineNames.isEmpty ? '' : '${pipelineNames.first} (frame where not cropped)'} / perfect crop)\n',
  );
  b.writeln(
    '| category | pages | CER frame | CER pipeline | CER oracle | recall frame | recall pipeline | recall oracle | reading order frame | pipeline | oracle |',
  );
  b.writeln('|---|---|---|---|---|---|---|---|---|---|---|');
  for (final cat in cats) {
    final ms = [
      for (final m in byId.values)
        if (m['frame']!.category == cat) m,
    ];
    if (ms.isEmpty) continue;
    String oc(double Function(OcrRow) f) {
      final o = [
        for (final m in ms)
          if (m['oracle'] != null) f(m['oracle']!),
      ];
      return o.isEmpty ? '-' : _f(_mean(o));
    }

    final first = pipelineNames.isEmpty ? 'frame' : pipelineNames.first;
    b.writeln(
      '| $cat | ${ms.length} | ${_f(_mean(ms.map((m) => m['frame']!.cer)))} | '
      '${_f(_mean(ms.map((m) => m[first]!.cer)))} | ${oc((r) => r.cer)} | '
      '${_f(_mean(ms.map((m) => m['frame']!.wordRecall)), 2)} | ${_f(_mean(ms.map((m) => m[first]!.wordRecall)), 2)} | ${oc((r) => r.wordRecall)} | '
      '${_f(_mean(ms.map((m) => m['frame']!.order)), 2)} | ${_f(_mean(ms.map((m) => m[first]!.order)), 2)} | ${oc((r) => r.order)} |',
    );
  }
  b.writeln();

  // Tilted two-column receipts.
  final tilted = [
    for (final m in byId.values)
      if (m['frame']!.pairing >= 0) m,
  ];
  if (tilted.isNotEmpty) {
    b.writeln(
      '#### Tilted two-column receipts: does a label keep its own value? (share of the 14 label-value pairs read in the right order; the pages are the roll angles 0, 5, 10, 15, -10, -15 degrees in id order)',
    );
    b.writeln();
    final names = ['frame', 'oracle', ...pipelineNames];
    b.writeln('| page | ${names.join(' | ')} |');
    b.writeln('|---|${names.map((_) => '---').join('|')}|');
    for (final m in tilted) {
      b.writeln(
        '| ${m['frame']!.id} | ${names.map((n) => m[n] == null ? '-' : _f(m[n]!.pairing, 2)).join(' | ')} |',
      );
    }
    b.writeln(
      '| **mean** | ${names.map((n) => _f(_mean([for (final m in tilted)
        if (m[n] != null) m[n]!.pairing]), 3)).join(' | ')} |',
    );
    b.writeln();
  }

  // Safety checks.
  b.writeln(
    '#### Safety check after the crop: when it triggers, the crop is replaced by the whole frame\n',
  );
  b.writeln(
    '"Lost" = the crop really lost more than ${(tolerance * 100).toStringAsFixed(0)} points of word recall against the known text (ground truth, not available to the app). '
    'Both checks need the OCR of the crop **and** of the whole frame (one extra OCR pass per cropped page, the "frame" time in the table above). '
    '*Word count*: the crop gives fewer words than the frame. '
    '*Frame-text coverage*: fewer than the given share of the words read in the frame are read in the crop.\n',
  );
  b.writeln(
    '| pipeline | check | cropped pages | crops that lost words | triggered | triggered and really lost | triggered, crop was fine | lost and **not caught** | mean CER change before check | after check |',
  );
  b.writeln('|---|---|---|---|---|---|---|---|---|---|');
  final checks = <(String, bool Function(OcrRow, OcrRow))>[
    ('word count < 90%', (f, c) => c.ocrWords < 0.9 * f.ocrWords),
    ('word count < 97%', (f, c) => c.ocrWords < 0.97 * f.ocrWords),
    ('frame-text coverage < 95%', (f, c) => c.frameCoverage < 0.95),
    ('frame-text coverage < 98%', (f, c) => c.frameCoverage < 0.98),
  ];
  for (final c in pipelineNames) {
    final pairs = [
      for (final m in byId.values)
        if (m[c] != null && m[c]!.used) (m['frame']!, m[c]!),
    ];
    if (pairs.isEmpty) continue;
    bool lost((OcrRow, OcrRow) p) =>
        p.$1.wordRecall - p.$2.wordRecall > tolerance;
    for (final (name, fn) in checks) {
      bool trig((OcrRow, OcrRow) p) => fn(p.$1, p.$2);
      final after = [for (final p in pairs) trig(p) ? p.$1 : p.$2];
      b.writeln(
        '| $c | $name | ${pairs.length} | ${pairs.where(lost).length} | ${pairs.where(trig).length} | '
        '${pairs.where((p) => lost(p) && trig(p)).length} | ${pairs.where((p) => !lost(p) && trig(p)).length} | '
        '**${pairs.where((p) => lost(p) && !trig(p)).length}** | '
        '${_f(_mean(pairs.map((p) => p.$2.cer - p.$1.cer)))} | '
        '${_f(_mean([for (var i = 0; i < pairs.length; i++) after[i].cer - pairs[i].$1.cer]))} |',
      );
    }
  }
  b.writeln();

  // Times.
  b.writeln(
    '#### Times per page (ms, medians of the pages where the crop was used)\n',
  );
  b.writeln(
    '| pipeline | detection + confidence | warp | crop size (median) |',
  );
  b.writeln('|---|---|---|---|');
  for (final c in pipelineNames) {
    final used = [
      for (final r in rows)
        if (r.condition == c && r.used) r,
    ];
    if (used.isEmpty) continue;
    double med(Iterable<double> v) {
      final s = v.toList()..sort();
      return s[s.length ~/ 2];
    }

    final sizes = used.map((r) => r.cropWidth * r.cropHeight / 1e6);
    b.writeln(
      '| $c | ${_f(med(used.map((r) => r.detectMs)), 1)} | ${_f(med(used.map((r) => r.warpMs)), 1)} | ${_f(med(sizes), 2)} MP |',
    );
  }
  b.writeln();
  return b.toString();
}
