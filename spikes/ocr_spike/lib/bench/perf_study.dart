import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../engines/ocr_engine.dart';
import '../engines/paddle/paddle_config.dart';
import '../engines/paddle_engine.dart';
import '../engines/paddle_isolate.dart';
import 'device_info.dart';
import 'perf_lab.dart';
import 'render.dart';
import 'sample_guard.dart';
import 'runner.dart';
import 'text_metrics.dart';

/// Phase 1.6b: controlled phone measurements. Everything here prints numbers
/// only. Text recognised from a picked image stays in memory for the
/// comparison and is never written, logged or copied.

// -------------------------------------------------------------------- UI load

/// How hard the Perf screen itself works while OCR runs.
enum UiLoad {
  /// Spinner at the full frame rate of the display.
  max,

  /// Nothing animates (the screen is on, no frames are produced).
  still,

  /// One tiny repaint per second.
  low,
}

/// Read by the indicator on the Perf screen, set by the studies. Starts at
/// `low`: what a processing screen in Scan would do.
final ValueNotifier<UiLoad> uiLoad = ValueNotifier(UiLoad.low);

double? displayRefreshRate() {
  try {
    final views = PlatformDispatcher.instance.views;
    return views.isEmpty ? null : views.first.display.refreshRate;
  } catch (_) {
    return null;
  }
}

Future<String> envLine() async =>
    'device $deviceTag, display ${displayRefreshRate()?.toStringAsFixed(0) ?? 'n/a'} Hz, '
    'battery ${tempText(await batteryTempC())} C';

/// Providers this ONNX Runtime build offers. The plugin does not say which
/// one a session really ran on (an unsupported operator falls back to CPU),
/// so timings and result differences are the only evidence.
Future<String> providersLine() async {
  try {
    final names = (await OnnxRuntime().getAvailableProviders()).map(
      (p) => p.name,
    );
    return 'available providers ${names.join(', ')}';
  } catch (_) {
    return 'available providers unknown';
  }
}

typedef LineSink = void Function(String line);

void _emit(LineSink sink, String line) {
  sink(line);
}

// ------------------------------------------------------------------- settings

/// Native decode 2560, ArgMax model, typed loops, batch 1, isolate, 4 threads,
/// CPU: the fixed setting of the UI-load study.
final PaddleConfig studyConfig = finalConfig.copyWith(recBatch: 1);

String describeConfig(PaddleConfig c) =>
    'th${c.threads} ${c.providers?.map((p) => p.name).join('+') ?? 'default-provider'} '
    'spin ${c.allowSpinning ?? 'default'} batch ${c.recBatch} det ${c.detSide} '
    'decode ${c.decode.name}/${c.maxSide} iso ${c.isolate} fast ${c.fastPixels} '
    'argmax ${c.recArgmax}';

double _mean(Iterable<num> v) =>
    v.isEmpty ? 0 : v.fold<num>(0, (a, b) => a + b) / v.length;

double _median(Iterable<num> v) {
  if (v.isEmpty) return 0;
  final s = <num>[...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m].toDouble() : (s[m - 1] + s[m]) / 2;
}

String _f(num v) => v.round().toString();

// ------------------------------------------------------------------ A: UI load

class _StudyRun {
  _StudyRun(
    this.block,
    this.state,
    this.index,
    this.totalMs,
    this.recMs,
    this.detMs,
    this.frames,
    this.secs,
    this.tempBefore,
    this.tempAfter,
  );
  final int block, index;
  final UiLoad state;
  final int totalMs, recMs, detMs, frames;
  final double secs;
  final double? tempBefore, tempAfter;
}

const uiStudyOrder = [
  UiLoad.max,
  UiLoad.still,
  UiLoad.low,
  UiLoad.low,
  UiLoad.still,
  UiLoad.max,
];

/// 5 warm runs per UI state in the order a b c c b a, [pauseSec] of rest
/// between the states, one fixed setting, one image. Reports `recRun`, total,
/// frames and the battery temperature when the system gives it.
Future<void> runUiLoadStudy({
  required File image,
  required String imageLabel,
  required int pauseSec,
  required PerfProgress progress,
  required LineSink out,
  int runsPerState = 5,
}) async {
  _emit(out, 'A: UI load study. ${await envLine()}; ${await providersLine()}');
  _emit(
    out,
    'A: image $imageLabel; setting ${describeConfig(studyConfig)}; '
    'order ${uiStudyOrder.map((s) => s.name).join(',')}; '
    '$runsPerState runs per state, pause $pauseSec s',
  );
  await PaddleEngine.releaseAll();
  final engine = PerfExperiment(
    'study',
    'study',
    'ui load study',
    studyConfig,
  ).build('greek');
  final runs = <_StudyRun>[];
  try {
    uiLoad.value = UiLoad.still;
    progress('A: loading and warming up');
    await engine.prepare();
    for (var i = 0; i < 2; i++) {
      await engine.recognize(image.path);
    }
    for (var b = 0; b < uiStudyOrder.length; b++) {
      final state = uiStudyOrder[b];
      uiLoad.value = state;
      await Future<void>.delayed(const Duration(seconds: 1));
      for (var i = 1; i <= runsPerState; i++) {
        progress(
          'A: block ${b + 1}/${uiStudyOrder.length} ${state.name} run $i',
        );
        final t0 = await batteryTempC();
        final monitor = JankMonitor(light: true)..start();
        final r = await engine.recognize(image.path);
        final jank = monitor.stop();
        final t1 = await batteryTempC();
        if (r.error != null) {
          _emit(out, 'A: ERROR ${r.error}');
          return;
        }
        final run = _StudyRun(
          b + 1,
          state,
          i,
          r.elapsedMs,
          ((r.breakdown['us_recInfer'] ?? 0) / 1000).round(),
          ((r.breakdown['us_detInfer'] ?? 0) / 1000).round(),
          jank.frames,
          jank.seconds,
          t0,
          t1,
        );
        runs.add(run);
        _emit(
          out,
          'A b${run.block} ${state.name} r$i: total ${run.totalMs} ms, '
          'recRun ${run.recMs}, detRun ${run.detMs}, '
          'ui ${run.frames} fr/${run.secs.toStringAsFixed(1)} s, '
          'temp ${tempText(t0)}->${tempText(t1)} C',
        );
      }
      uiLoad.value = UiLoad.still;
      if (b < uiStudyOrder.length - 1) {
        for (var s = pauseSec; s > 0; s--) {
          progress('A: pause $s s');
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
    }
  } finally {
    uiLoad.value = UiLoad.low;
    await engine.dispose();
    await PaddleEngine.releaseAll();
  }
  _studySummary(runs, out);
}

void _studySummary(List<_StudyRun> runs, LineSink out) {
  if (runs.isEmpty) return;
  final blocks = {for (final r in runs) r.block};
  for (final b in blocks) {
    final rs = runs.where((r) => r.block == b).toList();
    final fps = _mean([for (final r in rs) r.frames / math.max(r.secs, 0.001)]);
    _emit(
      out,
      'A block $b ${rs.first.state.name}: recRun mean ${_f(_mean([for (final r in rs) r.recMs]))} '
      '(${_f(rs.map((r) => r.recMs).reduce(math.min))}..${_f(rs.map((r) => r.recMs).reduce(math.max))}), '
      'total mean ${_f(_mean([for (final r in rs) r.totalMs]))}, '
      'ui ${fps.toStringAsFixed(1)} fr/s, '
      'temp ${tempText(rs.first.tempBefore)}->${tempText(rs.last.tempAfter)} C',
    );
  }
  double recOf(UiLoad s) => _mean([
    for (final r in runs)
      if (r.state == s) r.recMs,
  ]);
  double totOf(UiLoad s) => _mean([
    for (final r in runs)
      if (r.state == s) r.totalMs,
  ]);
  for (final s in UiLoad.values) {
    final v = [
      for (final r in runs)
        if (r.state == s) r.recMs,
    ];
    _emit(
      out,
      'A pooled ${s.name} (n=${v.length}): recRun mean ${_f(recOf(s))}, '
      'median ${_f(_median(v))}, total mean ${_f(totOf(s))}',
    );
  }
  String delta(UiLoad a, UiLoad b) {
    final d = recOf(a) - recOf(b);
    return '${d >= 0 ? '+' : ''}${_f(d)} ms (${(100 * d / recOf(b)).toStringAsFixed(1)}%)';
  }

  _emit(
    out,
    'A effect on recRun: max vs still ${delta(UiLoad.max, UiLoad.still)}, '
    'low vs still ${delta(UiLoad.low, UiLoad.still)}, '
    'max vs low ${delta(UiLoad.max, UiLoad.low)}',
  );
  // Drift: the same state at both ends of the order (a ... a, b ... b).
  for (final s in [UiLoad.max, UiLoad.still, UiLoad.low]) {
    final bs =
        runs.where((r) => r.state == s).map((r) => r.block).toSet().toList()
          ..sort();
    if (bs.length < 2) continue;
    final first = _mean([
      for (final r in runs)
        if (r.block == bs.first) r.recMs,
    ]);
    final last = _mean([
      for (final r in runs)
        if (r.block == bs.last) r.recMs,
    ]);
    _emit(
      out,
      'A drift ${s.name}: first visit ${_f(first)} -> last visit ${_f(last)} ms '
      '(${(100 * (last - first) / first).toStringAsFixed(1)}%)',
    );
  }
}

// -------------------------------------------------------------- B: provider grid

const _gridProviders = <String, List<OrtProvider>?>{
  'cpu': null,
  'xnnpack': [OrtProvider.XNNPACK, OrtProvider.CPU],
  'nnapi': [OrtProvider.NNAPI, OrtProvider.CPU],
};

/// Threads {2,3,4} x provider {CPU, XNNPACK, NNAPI}, spinning off. The page
/// runs the list forward and then backwards (pass 1 and 2): the difference
/// between the passes of the same cell is the noise and drift estimate.
List<PerfExperiment> buildGridExperiments() {
  final base = studyConfig.copyWith(allowSpinning: false);
  PerfExperiment cell(String id, String p, int t) => PerfExperiment(
    id,
    'grid',
    '$p $t threads',
    base.copyWith(threads: t, providers: _gridProviders[p]),
  );
  return [
    for (final t in [2, 3, 4])
      for (final p in _gridProviders.keys) cell('g_${p}_t$t', p, t),
  ];
}

String providerOf(PaddleConfig c) =>
    (c.providers == null ? 'cpu' : c.providers!.first.name).toLowerCase();

/// One finished grid cell, from a live run or from the saved log.
class GridPoint {
  GridPoint(this.expId, this.pass, this.warmMs, this.ok);
  final String expId, pass;
  final double warmMs;
  final bool ok;

  factory GridPoint.fromCell(PerfCell c, String pass) => GridPoint(
    c.exp.id,
    pass,
    c.warmMean.toDouble(),
    c.error == null && c.skipped == null,
  );

  factory GridPoint.fromJson(Map<String, Object?> j, String pass) => GridPoint(
    j['exp'] as String,
    pass,
    ((j['warmMean'] as num?) ?? 0).toDouble(),
    j['error'] == null && j['skipped'] == null,
  );
}

/// Mean warm total per experiment over scenarios and passes (an experiment
/// with an error anywhere is dropped).
Map<String, double> gridMeans(List<GridPoint> points) {
  final byExp = <String, List<GridPoint>>{};
  for (final p in points) {
    byExp.putIfAbsent(p.expId, () => []).add(p);
  }
  return {
    for (final e in byExp.entries)
      if (e.value.every((p) => p.ok))
        e.key: _mean([for (final p in e.value) p.warmMs]),
  };
}

/// Run-to-run noise: the median relative difference between pass 1 and pass 2
/// of the same experiment (0 when there is only one pass).
double gridNoise(List<GridPoint> points) {
  final diffs = <double>[];
  final ids = {for (final p in points) p.expId};
  for (final id in ids) {
    double? m(String pass) {
      final v = [
        for (final p in points)
          if (p.expId == id && p.pass == pass && p.ok) p.warmMs,
      ];
      return v.isEmpty ? null : _mean(v);
    }

    final a = m('p1'), b = m('p2');
    if (a != null && b != null) diffs.add((a - b).abs() / ((a + b) / 2));
  }
  return diffs.isEmpty ? 0 : _median(diffs);
}

/// A setting must beat the CPU/4-thread cell by more than this share: twice
/// the noise seen between the passes, at least 5%.
double gridMargin(List<GridPoint> points) =>
    math.max(0.05, 2 * gridNoise(points));

/// Fastest grid setting among the providers that are not excluded, but only
/// when it beats the CPU/4-thread cell by more than [gridMargin] (otherwise
/// that cell).
({PaddleConfig config, String label}) chooseBest(
  List<GridPoint> points,
  Set<String> excludedProviders,
) {
  final means = gridMeans(points);
  final exps = {for (final e in buildGridExperiments()) e.id: e};
  String? best;
  for (final id in means.keys) {
    if (excludedProviders.contains(providerOf(exps[id]!.config))) continue;
    if (best == null || means[id]! < means[best]!) best = id;
  }
  const baseId = 'g_cpu_t4';
  if (best == null || !means.containsKey(baseId)) return provisionalBest;
  if (best != baseId &&
      means[best]! > (1 - gridMargin(points)) * means[baseId]!) {
    best = baseId;
  }
  return (
    config: exps[best]!.config,
    label: '$best (mean warm ${_f(means[best]!)} ms)',
  );
}

/// What "best" means before any phone measurement exists.
final provisionalBest = (
  config: studyConfig.copyWith(allowSpinning: false),
  label: 'provisional (th4 CPU spin off; no grid measured yet)',
);

// --------------------------------------------------------- C: provider accuracy

double _iou(Rect a, Rect b) {
  final i = a.intersect(b);
  if (i.width <= 0 || i.height <= 0) return 0;
  final ia = i.width * i.height;
  return ia / (a.width * a.height + b.width * b.height - ia);
}

/// Differences of one candidate from the reference over several images.
class ResultDiff {
  int images = 0, refLines = 0, candLines = 0;
  int identical = 0, unmatchedRef = 0, extraCand = 0;
  int distanceSum = 0, matched = 0;
  double confDeltaSum = 0;
  int confImages = 0;

  void add(OcrResult ref, OcrResult cand) {
    images++;
    refLines += ref.lines.length;
    candLines += cand.lines.length;
    final used = <int>{};
    for (final r in ref.lines) {
      var bestJ = -1;
      var bestIou = 0.5;
      for (var j = 0; j < cand.lines.length; j++) {
        if (used.contains(j)) continue;
        final v = _iou(r.box, cand.lines[j].box);
        if (v >= bestIou) {
          bestIou = v;
          bestJ = j;
        }
      }
      if (bestJ < 0) {
        unmatchedRef++;
        continue;
      }
      used.add(bestJ);
      matched++;
      final a = r.text, b = cand.lines[bestJ].text;
      if (a == b) {
        identical++;
      } else {
        distanceSum += align(chars(a), chars(b)).distance;
      }
    }
    extraCand += cand.lines.length - used.length;
    if (ref.confidence != null && cand.confidence != null) {
      confDeltaSum += cand.confidence! - ref.confidence!;
      confImages++;
    }
  }

  bool get sameAsReference =>
      refLines == candLines &&
      unmatchedRef == 0 &&
      extraCand == 0 &&
      identical == refLines;

  String line(String name) {
    final pct = refLines == 0 ? 100 : 100 * identical / refLines;
    return '$name: images $images, boxes $candLines vs $refLines ref, '
        'identical lines ${pct.toStringAsFixed(1)}% ($identical/$refLines), '
        'unmatched ref $unmatchedRef, extra $extraCand, '
        'mean distance ${(distanceSum / math.max(1, matched)).toStringAsFixed(3)} ch/line, '
        'mean confidence change ${confImages == 0 ? 'n/a' : (confDeltaSum / confImages).toStringAsFixed(4)}';
  }
}

class ProviderAccuracyOutcome {
  ProviderAccuracyOutcome(this.excluded);

  /// Provider names whose results differ from the CPU reference.
  final Set<String> excluded;
}

/// Runs the CPU reference, a second CPU run (noise floor) and the XNNPACK and
/// NNAPI settings on [images], compares line by line, then runs the synthetic
/// accuracy set (CER, key tokens) through the same four settings.
Future<ProviderAccuracyOutcome> runProviderAccuracy({
  required Map<String, File> images,
  required int threads,
  required PerfProgress progress,
  required LineSink out,
  bool syntheticSet = true,
}) async {
  _emit(
    out,
    'C: provider accuracy. ${await envLine()}; ${await providersLine()}; '
    'threads $threads, spin off',
  );
  final base = studyConfig.copyWith(allowSpinning: false, threads: threads);
  final settings = <String, PaddleConfig>{
    'cpu': base,
    'cpu_again': base,
    'xnnpack': base.copyWith(providers: _gridProviders['xnnpack']),
    'nnapi': base.copyWith(providers: _gridProviders['nnapi']),
  };
  final results = <String, Map<String, OcrResult>>{};
  for (final e in settings.entries) {
    await PaddleEngine.releaseAll();
    final engine = PerfExperiment(
      'acc_${e.key}',
      'acc',
      e.key,
      e.value,
    ).build('greek');
    final per = <String, OcrResult>{};
    try {
      progress('C: ${e.key} loading');
      await engine.prepare();
      for (final img in images.entries) {
        progress('C: ${e.key} ${img.key}');
        per[img.key] = await engine.recognize(img.value.path);
      }
    } finally {
      await engine.dispose();
    }
    results[e.key] = per;
  }
  await PaddleEngine.releaseAll();
  final excluded = <String>{};
  final ref = results['cpu']!;
  for (final name in ['cpu_again', 'xnnpack', 'nnapi']) {
    final total = ResultDiff();
    for (final img in images.keys) {
      final r = ref[img]!, c = results[name]![img]!;
      if (r.error != null || c.error != null) {
        _emit(out, 'C $name $img: ERROR ${r.error ?? c.error}');
        continue;
      }
      final d = ResultDiff()..add(r, c);
      total.add(r, c);
      _emit(out, d.line('C $name $img'));
    }
    _emit(out, total.line('C TOTAL $name vs cpu'));
    if (name != 'cpu_again' && !total.sameAsReference) excluded.add(name);
    _emit(
      out,
      name == 'cpu_again'
          ? 'C noise floor (same CPU setting twice): '
                '${total.sameAsReference ? 'identical' : 'DIFFERENT, run-to-run variation exists'}'
          : 'C VERDICT $name: ${total.sameAsReference ? 'results identical to CPU on these images' : 'results CHANGED compared with CPU'}',
    );
  }
  if (syntheticSet) {
    final engines = [
      for (final e in settings.entries)
        if (e.key != 'cpu_again')
          EngineConfig(
            'paddle_${e.key}',
            (l) => PerfExperiment(
              'acc_${e.key}',
              'acc',
              e.key,
              e.value,
            ).build(paddleKeyFor(l)),
          ),
    ];
    final records = await runSynthetic(
      conditions: [
        Condition.clean,
        Condition.rot3,
        Condition.blur,
        Condition.lowContrastNoise,
      ],
      engines: engines,
      progress: (m) => progress('C synthetic: $m'),
      emit: false,
    );
    for (final s in summarize(records).values) {
      _emit(out, 'C synthetic ${s.line}');
    }
  }
  return ProviderAccuracyOutcome(excluded);
}

// ------------------------------------------------------------ F: paired A/B

class _Pair {
  _Pair(this.which, this.round, this.pos, this.totalMs, this.recMs);
  final String which; // 'A' or 'B'
  final int round, pos; // pos: 0 = first in the round, 1 = second
  final int totalMs, recMs;
}

/// Two arms measured alternately (A B | B A | A B ...) on one image, so that
/// heat, the order and the time of the measurement hit both the same way.
/// Prints the means per arm, per position in the round (first or second) and
/// the drift from the first to the last third. Without [configB] the arms are
/// two recognition batch sizes ([batchA], [batchB]) of one engine with the
/// same loaded sessions; with [configB] they are two complete pipelines
/// ([config] against [configB], each in its own engine). With identical arms
/// it is the control: any difference between A and B (or between first and
/// second) is order or noise.
Future<void> runPairedAB({
  required String name,
  required PaddleConfig config,
  PaddleConfig? configB,
  int batchA = 1,
  int batchB = 1,
  required File image,
  required PerfProgress progress,
  required LineSink out,
  int rounds = 6,
}) async {
  final dims = imageSize(image);
  final mp = dims == null ? null : dims.w * dims.h / 1e6;
  final va = guardRun(
    configB == null ? config.copyWith(isolate: true) : config,
    mp,
  );
  final vb = configB == null ? va : guardRun(configB, mp);
  if (va.skipped || vb.skipped) {
    out('F $name: ${va.skipReason ?? vb.skipReason}');
    return;
  }
  await PaddleEngine.releaseAll();
  final SpikeOcrEngine engineA;
  SpikeOcrEngine? engineB;
  if (configB == null) {
    engineA = IsolatePaddleEngine(
      'greek',
      va.config.copyWith(recBatch: batchA),
    );
  } else {
    engineA = PerfExperiment('pair_a', 'pair', name, va.config).build('greek');
    engineB = PerfExperiment('pair_b', 'pair', name, vb.config).build('greek');
  }
  final runs = <_Pair>[];
  Future<OcrResult> one(String which) async {
    if (engineB != null) {
      return (which == 'A' ? engineA : engineB).recognize(image.path);
    }
    await (engineA as IsolatePaddleEngine).setRecBatch(
      which == 'A' ? batchA : batchB,
    );
    return engineA.recognize(image.path);
  }

  try {
    progress('F: $name loading');
    await engineA.prepare();
    await engineB?.prepare();
    for (var i = 0; i < 2; i++) {
      await one('A');
      await one('B');
    }
    for (var r = 0; r < rounds; r++) {
      final order = r.isEven ? ['A', 'B'] : ['B', 'A'];
      for (var pos = 0; pos < 2; pos++) {
        final which = order[pos];
        progress('F: $name round ${r + 1}/$rounds $which');
        final res = await one(which);
        if (res.error != null) {
          out('F $name: ERROR ${res.error}');
          return;
        }
        runs.add(
          _Pair(
            which,
            r,
            pos,
            res.elapsedMs,
            ((res.breakdown['us_recInfer'] ?? 0) / 1000).round(),
          ),
        );
      }
    }
  } finally {
    await engineA.dispose();
    await engineB?.dispose();
    await PaddleEngine.releaseAll();
  }
  String stat(Iterable<_Pair> v, String what) {
    final t = [for (final x in v) x.totalMs];
    final r = [for (final x in v) x.recMs];
    return '$what n=${t.length}: total mean ${_f(_mean(t))} median ${_f(_median(t))}, '
        'recRun mean ${_f(_mean(r))} median ${_f(_median(r))} '
        '(${_f(r.reduce(math.min))}..${_f(r.reduce(math.max))})';
  }

  if (configB == null) {
    out(
      'F $name: ${describeConfig(va.config)}; A = batch $batchA, B = batch $batchB',
    );
  } else {
    out('F $name: A = ${describeConfig(va.config)}');
    out('F $name: B = ${describeConfig(vb.config)}');
  }
  out('F $name ${stat(runs.where((x) => x.which == 'A'), 'A')}');
  out('F $name ${stat(runs.where((x) => x.which == 'B'), 'B')}');
  out('F $name ${stat(runs.where((x) => x.pos == 0), 'first of round')}');
  out('F $name ${stat(runs.where((x) => x.pos == 1), 'second of round')}');
  final third = runs.length ~/ 3;
  final early = _mean([for (final x in runs.take(third)) x.recMs]);
  final late = _mean([for (final x in runs.skip(runs.length - third)) x.recMs]);
  final ra = _mean([
    for (final x in runs)
      if (x.which == 'A') x.recMs,
  ]);
  final rb = _mean([
    for (final x in runs)
      if (x.which == 'B') x.recMs,
  ]);
  out(
    'F $name drift: recRun first third ${_f(early)} -> last third ${_f(late)} '
    '(${(100 * (late - early) / early).toStringAsFixed(1)}%); '
    'B vs A recRun ${(100 * (rb - ra) / ra).toStringAsFixed(1)}%',
  );
}
