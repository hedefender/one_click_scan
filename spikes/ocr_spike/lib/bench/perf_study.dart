import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../engines/ocr_engine.dart';
import '../engines/paddle/paddle_config.dart';
import '../engines/paddle_engine.dart';
import 'perf_lab.dart';
import 'render.dart';
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

/// Battery temperature in °C if the system lets an app read it (sysfs,
/// tenths of a degree). Null when not readable: then no temperature is
/// reported rather than guessed.
double? batteryTempC() {
  for (final path in const [
    '/sys/class/power_supply/battery/temp',
    '/sys/class/power_supply/Battery/temp',
  ]) {
    try {
      final raw = File(path).readAsStringSync().trim();
      final v = int.tryParse(raw);
      if (v != null) return v / 10;
    } catch (_) {}
  }
  return null;
}

String _t(double? c) => c == null ? 'n/a' : c.toStringAsFixed(1);

String envLine() =>
    'device $deviceTag, display ${displayRefreshRate()?.toStringAsFixed(0) ?? 'n/a'} Hz, '
    'battery ${_t(batteryTempC())} C';

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
  // ignore: avoid_print
  print('PERFSTUDY $line');
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

double _mean(List<num> v) =>
    v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

double _median(List<num> v) {
  if (v.isEmpty) return 0;
  final s = [...v]..sort();
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
  _emit(out, 'A: UI load study. ${envLine()}; ${await providersLine()}');
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
        final t0 = batteryTempC();
        final monitor = JankMonitor(light: true)..start();
        final r = await engine.recognize(image.path);
        final jank = monitor.stop();
        final t1 = batteryTempC();
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
          'temp ${_t(t0)}->${_t(t1)} C',
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
      'temp ${_t(rs.first.tempBefore)}->${_t(rs.last.tempAfter)} C',
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

/// Threads {2,3,4} x provider {CPU, XNNPACK, NNAPI}, spinning off, plus two
/// repeats of the first cell at the end (`_ctl`) to show drift.
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
    cell('g_cpu_t2_ctl', 'cpu', 2),
    cell('g_cpu_t4_ctl', 'cpu', 4),
  ];
}

String providerOf(PaddleConfig c) =>
    (c.providers == null ? 'cpu' : c.providers!.first.name).toLowerCase();

/// Mean warm total per experiment over its scenarios (errors drop the
/// experiment).
Map<String, double> gridMeans(List<PerfCell> cells) {
  final byExp = <String, List<PerfCell>>{};
  for (final c in cells) {
    byExp.putIfAbsent(c.exp.id, () => []).add(c);
  }
  return {
    for (final e in byExp.entries)
      if (e.value.every((c) => c.error == null))
        e.key: _mean([for (final c in e.value) c.warmMean]),
  };
}

/// Run-to-run noise seen in the repeated cells (`_ctl`), at least 5%: a
/// setting must beat the CPU/4-thread cell by more than this to be chosen.
double gridMargin(Map<String, double> means) {
  var noise = 0.05;
  for (final id in ['g_cpu_t2', 'g_cpu_t4']) {
    final a = means[id], b = means['${id}_ctl'];
    if (a != null && b != null) noise = math.max(noise, (a - b).abs() / a);
  }
  return noise;
}

/// Fastest grid setting among the providers that are not excluded, but only
/// when it beats the CPU/4-thread cell by more than 5% (otherwise that cell).
({PaddleConfig config, String label}) chooseBest(
  List<PerfCell> grid,
  Set<String> excludedProviders,
) {
  final means = gridMeans(grid);
  final exps = {for (final c in grid) c.exp.id: c.exp};
  String? best;
  for (final id in means.keys) {
    if (id.endsWith('_ctl')) continue;
    if (excludedProviders.contains(providerOf(exps[id]!.config))) continue;
    if (best == null || means[id]! < means[best]!) best = id;
  }
  const baseId = 'g_cpu_t4';
  if (best == null || !means.containsKey(baseId)) return provisionalBest;
  if (best != baseId &&
      means[best]! > (1 - gridMargin(means)) * means[baseId]!) {
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
    'C: provider accuracy. ${envLine()}; ${await providersLine()}; '
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
