import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

import '../engines/ocr_engine.dart';
import '../engines/paddle/paddle_config.dart';
import '../engines/paddle_engine.dart';
import '../engines/paddle_isolate.dart';
import 'perf_scenarios.dart';
import 'text_metrics.dart';

/// `--dart-define=DEVICE=emulator|phone` labels the printed lines.
const deviceTag = String.fromEnvironment('DEVICE', defaultValue: 'unknown');

// ---------------------------------------------------------------- experiments

class PerfExperiment {
  const PerfExperiment(
    this.id,
    this.group,
    this.title,
    this.config, {
    this.sizes = const [PhotoSize.native],
  });

  final String id;
  final String group;
  final String title;
  final PaddleConfig config;

  /// Photo sizes this experiment runs on (camera = about 12 MP).
  final List<PhotoSize> sizes;

  SpikeOcrEngine build(String recKey) => config.isolate
      ? IsolatePaddleEngine(recKey, config)
      : PaddleEngine(recKey, config: config);
}

const _both = [PhotoSize.native, PhotoSize.camera];
const _base = PaddleConfig();

/// One change at a time against [_base] (the Phase 1.5 pipeline), then the
/// combination that the numbers support (`final`).
final List<PerfExperiment> perfExperiments = [
  const PerfExperiment(
    'base',
    'baseline',
    'Phase 1.5 pipeline',
    _base,
    sizes: _both,
  ),
  // 2. ONNX Runtime settings
  PerfExperiment('th1', 'ort', '1 thread', _base.copyWith(threads: 1)),
  PerfExperiment('th2', 'ort', '2 threads', _base.copyWith(threads: 2)),
  PerfExperiment('th6', 'ort', '6 threads', _base.copyWith(threads: 6)),
  PerfExperiment('th8', 'ort', '8 threads', _base.copyWith(threads: 8)),
  PerfExperiment(
    'xnnpack',
    'ort',
    'XNNPACK + CPU',
    _base.copyWith(providers: [OrtProvider.XNNPACK, OrtProvider.CPU]),
  ),
  PerfExperiment(
    'nnapi',
    'ort',
    'NNAPI + CPU',
    _base.copyWith(providers: [OrtProvider.NNAPI, OrtProvider.CPU]),
  ),
  PerfExperiment(
    'nospin',
    'ort',
    'no thread spinning',
    _base.copyWith(allowSpinning: false),
  ),
  // 3. detection input size
  PerfExperiment(
    'det640',
    'det',
    'detection 640',
    _base.copyWith(detSide: 640),
  ),
  PerfExperiment(
    'det800',
    'det',
    'detection 800',
    _base.copyWith(detSide: 800),
  ),
  PerfExperiment(
    'det1280',
    'det',
    'detection 1280',
    _base.copyWith(detSide: 1280),
  ),
  // 4. recognition batching
  PerfExperiment(
    'batch4',
    'batch',
    'recognition batch 4',
    _base.copyWith(recBatch: 4),
  ),
  PerfExperiment(
    'batch8',
    'batch',
    'recognition batch 8',
    _base.copyWith(recBatch: 8),
  ),
  // 5. pre/post-processing and decoding
  PerfExperiment(
    'fast',
    'pre',
    'typed-list pixel loops',
    _base.copyWith(fastPixels: true),
  ),
  PerfExperiment(
    'nat',
    'decode',
    'native decode, full size',
    _base.copyWith(decode: DecodeMode.native),
    sizes: _both,
  ),
  PerfExperiment(
    'nat2560',
    'decode',
    'native decode, max side 2560',
    _base.copyWith(decode: DecodeMode.native, maxSide: 2560),
    sizes: _both,
  ),
  PerfExperiment(
    'nat1600',
    'decode',
    'native decode, max side 1600',
    _base.copyWith(decode: DecodeMode.native, maxSide: 1600),
    sizes: _both,
  ),
  PerfExperiment(
    'am',
    'pre',
    'argmax inside the recognition model',
    _base.copyWith(recArgmax: true),
  ),
  // 6. background isolate
  PerfExperiment(
    'iso',
    'isolate',
    'background isolate',
    _base.copyWith(isolate: true),
  ),
  PerfExperiment(
    'iso_fast',
    'isolate',
    'isolate + typed-list loops',
    _base.copyWith(isolate: true, fastPixels: true),
  ),
  // Combination chosen from the measurements (edit after the numbers are in).
  PerfExperiment('final', 'final', 'combination', finalConfig, sizes: _both),
  PerfExperiment(
    'final_b1',
    'final',
    'combination without batching',
    finalConfig.copyWith(recBatch: 1),
    sizes: _both,
  ),
];

/// Typed-list loops, native decode capped at 2560, batch 4, 4 threads, in a
/// background isolate. Thread count and detection size are the knobs to
/// settle on the phone.
const finalConfig = PaddleConfig(
  fastPixels: true,
  recArgmax: true,
  decode: DecodeMode.native,
  maxSide: 2560,
  recBatch: 4,
  isolate: true,
);

const perfGroups = [
  'baseline',
  'ort',
  'det',
  'batch',
  'pre',
  'decode',
  'isolate',
  'final',
];

// ------------------------------------------------------------------ results

class JankStats {
  const JankStats({
    required this.frames,
    required this.seconds,
    required this.slow,
    required this.worstFrameMs,
    required this.stallMs,
    required this.pingMs,
  });
  final int frames, slow;
  final double seconds, worstFrameMs, stallMs, pingMs;

  Map<String, Object> toJson() => {
    'frames': frames,
    'secs': double.parse(seconds.toStringAsFixed(1)),
    'slow': slow,
    'worstFrameMs': worstFrameMs.round(),
    'stallMs': stallMs.round(),
    'pingMs': pingMs.round(),
  };
}

/// Watches the UI while OCR runs: frame times, the longest gap between two
/// 8 ms timer ticks of the UI isolate, and the longest round trip of a
/// trivial platform-channel call (platform thread responsiveness).
class JankMonitor {
  /// [light] only counts frames: no timers and no channel pings, so the
  /// monitor itself adds no load (used where the load is the thing studied).
  JankMonitor({this.light = false});

  final bool light;
  final _sw = Stopwatch();
  var _frames = 0, _slow = 0;
  var _worstFrame = 0.0, _stall = 0.0, _ping = 0.0;
  Timer? _tick, _pingTimer;
  var _lastTick = 0;
  var _pinging = false;

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _frames++;
      final ms = t.totalSpan.inMicroseconds / 1000;
      if (ms > 16.7) _slow++;
      _worstFrame = math.max(_worstFrame, ms);
    }
  }

  void start() {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _sw.start();
    _lastTick = _sw.elapsedMicroseconds;
    if (light) return;
    _tick = Timer.periodic(const Duration(milliseconds: 8), (_) {
      final now = _sw.elapsedMicroseconds;
      _stall = math.max(_stall, (now - _lastTick) / 1000);
      _lastTick = now;
    });
    _pingTimer = Timer.periodic(const Duration(milliseconds: 25), (_) async {
      if (_pinging) return;
      _pinging = true;
      final t0 = _sw.elapsedMicroseconds;
      try {
        await Clipboard.hasStrings();
      } catch (_) {}
      _ping = math.max(_ping, (_sw.elapsedMicroseconds - t0) / 1000);
      _pinging = false;
    });
  }

  JankStats stop() {
    _tick?.cancel();
    _pingTimer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _sw.stop();
    return JankStats(
      frames: _frames,
      seconds: _sw.elapsedMilliseconds / 1000,
      slow: _slow,
      worstFrameMs: _worstFrame,
      stallMs: _stall,
      pingMs: _ping,
    );
  }
}

class PerfCell {
  PerfCell({
    required this.exp,
    required this.scenario,
    required this.size,
    required this.loadUs,
    required this.cold,
    required this.warm,
    required this.warmMs,
    required this.jank,
    this.cer,
    this.keysFound,
    this.keysTotal,
    this.chars = 0,
    this.error,
  });

  final PerfExperiment exp;
  final String scenario;
  final PhotoSize size;

  /// Session loading (cold), microseconds per part.
  final Map<String, int> loadUs;

  /// Breakdown of the cold run and the mean breakdown of the warm runs (µs;
  /// `us_*` stages plus counts).
  final Map<String, int> cold, warm;
  final List<int> warmMs;
  final JankStats jank;
  final double? cer;
  final int? keysFound, keysTotal;
  final int chars;
  final String? error;

  int get coldMs => ((cold['us_total'] ?? 0) / 1000).round();
  int get warmMean => ((warm['us_total'] ?? 0) / 1000).round();

  Map<String, Object?> toJson() => {
    'dev': deviceTag,
    'exp': exp.id,
    'scn': scenario,
    'size': size.name,
    'coldMs': coldMs,
    'warmMs': warmMs,
    'warmMean': warmMean,
    'loadUs': loadUs,
    'cold': cold,
    'warm': warm,
    'cer': cer == null ? null : double.parse((100 * cer!).toStringAsFixed(2)),
    'keys': keysFound == null ? null : [keysFound, keysTotal],
    'chars': chars,
    'jank': jank.toJson(),
    'error': error,
  };

  /// One line, numbers only (safe to paste).
  String get line {
    int ms(String k) => ((warm[k] ?? 0) / 1000).round();
    final decode =
        ms('us_read') +
        ms('us_decode') +
        ms('us_toRgb') +
        ms('us_toRgba') +
        ms('us_handover') +
        ms('us_materialize');
    if (error != null) {
      return '${exp.id} $scenario ${size.name}: ERROR $error';
    }
    return '${exp.id} $scenario ${size.name}: cold $coldMs ms, '
        'warm $warmMean ms [${warmMs.join('/')}] = '
        'dec $decode, detPre ${ms('us_detPre')}, '
        'detXfer ${ms('us_detIn') + ms('us_detOut') + ms('us_detConv')}, '
        'detRun ${ms('us_detInfer')}, detPost ${ms('us_detPost')}, '
        'recCrop ${ms('us_recCrop')}, '
        'recXfer ${ms('us_recIn') + ms('us_recOut')}, '
        'recRun ${ms('us_recInfer')}, ctc ${ms('us_recCtc')}, '
        'ipc ${ms('us_ipc')}; '
        'boxes ${warm['boxes']}, calls ${warm['recCalls']}, '
        'img ${warm['imgW']}x${warm['imgH']}, det ${warm['detW']}x${warm['detH']}; '
        'load ${(loadUs.values.fold<int>(0, (a, b) => a + b) / 1000).round()} ms; '
        '${cer == null ? '' : 'CER ${(100 * cer!).toStringAsFixed(1)}% keys $keysFound/$keysTotal; '}'
        'ui ${jank.frames} fr/${jank.seconds.toStringAsFixed(0)} s '
        'slow ${jank.slow} worst ${jank.worstFrameMs.round()} ms '
        'stall ${jank.stallMs.round()} ms ping ${jank.pingMs.round()} ms';
  }
}

// --------------------------------------------------------------------- runner

typedef PerfProgress = void Function(String message);

Map<String, int> _mean(List<Map<String, int>> runs) {
  final keys = {for (final r in runs) ...r.keys};
  return {
    for (final k in keys)
      k: (runs.map((r) => r[k] ?? 0).reduce((a, b) => a + b) / runs.length)
          .round(),
  };
}

Future<Directory> perfImageDir() async =>
    Directory('${(await getTemporaryDirectory()).path}/perf');

/// One cell of the matrix: load sessions from scratch, one cold run, then
/// [warmRuns] warm runs on the same image. [scenario] is null for a picked
/// real image (no accuracy numbers then).
Future<PerfCell> runPerfCell({
  required PerfExperiment exp,
  required String scenarioId,
  required PhotoSize size,
  required File image,
  PerfScenario? scenario,
  String recKey = 'greek',
  int warmRuns = 3,
  bool lightJank = false,
}) async {
  await PaddleEngine.releaseAll();
  final engine = exp.build(recKey);
  final monitor = JankMonitor(light: lightJank)..start();
  OcrResult? last;
  final runs = <OcrResult>[];
  Map<String, int> loadUs = const {};
  try {
    await engine.prepare();
    loadUs = engine is PaddleEngine
        ? engine.lastLoadUs
        : (engine as IsolatePaddleEngine).lastLoadUs;
    for (var i = 0; i < 1 + warmRuns; i++) {
      last = await engine.recognize(image.path);
      if (last.error != null) break;
      runs.add(last);
    }
  } catch (e) {
    last = OcrResult(text: '', elapsedMs: 0, error: '${e.runtimeType}');
  }
  final jank = monitor.stop();
  await engine.dispose();
  await PaddleEngine.releaseAll();
  if (runs.length < 1 + warmRuns) {
    return PerfCell(
      exp: exp,
      scenario: scenarioId,
      size: size,
      loadUs: loadUs,
      cold: runs.isEmpty ? const {} : runs.first.breakdown,
      warm: const {},
      warmMs: const [],
      jank: jank,
      error: last?.error ?? 'incomplete',
    );
  }
  final warm = runs.skip(1).toList();
  double? cer;
  int? found, total;
  if (scenario != null) {
    final s = score(scenario.spec.groundTruth, warm.last.text);
    cer = s.cer;
    final keys = scenario.spec.keys;
    total = keys.length;
    found = keys.values.where((v) => containsValue(warm.last.text, v)).length;
  }
  return PerfCell(
    exp: exp,
    scenario: scenarioId,
    size: size,
    loadUs: loadUs,
    cold: runs.first.breakdown,
    warm: _mean([for (final r in warm) r.breakdown]),
    warmMs: [for (final r in warm) r.elapsedMs],
    jank: jank,
    cer: cer,
    keysFound: found,
    keysTotal: total,
    chars: warm.last.text.length,
  );
}

var _chunkId = 0;

/// logcat cuts lines at about 1000 characters: `PERFBENCH <id> <i>/<n> text`.
void _emitChunked(String json) {
  const size = 700;
  final id = _chunkId++;
  final n = (json.length / size).ceil();
  for (var i = 0; i < n; i++) {
    final part = json.substring(
      i * size,
      math.min(json.length, (i + 1) * size),
    );
    // ignore: avoid_print
    print('PERFBENCH $id ${i + 1}/$n $part');
  }
}

/// Runs [experiments] on the three scenarios. Prints one `PERFBENCH {json}`
/// line per cell (synthetic data only) and returns the cells.
Future<List<PerfCell>> runPerfMatrix({
  required List<PerfExperiment> experiments,
  required PerfProgress progress,
  void Function(PerfCell cell)? onCell,
  bool emit = true,
  bool lightJank = false,
}) async {
  final dir = await perfImageDir();
  final cells = <PerfCell>[];
  for (final exp in experiments) {
    for (final scn in perfScenarios) {
      for (final size in exp.sizes) {
        progress('${exp.id} ${scn.id} ${size.name}: image');
        final file = await buildScenarioImage(scn, size, dir);
        progress('${exp.id} ${scn.id} ${size.name}');
        final cell = await runPerfCell(
          exp: exp,
          scenarioId: scn.id,
          size: size,
          image: file,
          scenario: scn,
          lightJank: lightJank,
        );
        cells.add(cell);
        onCell?.call(cell);
        if (emit) _emitChunked(jsonEncode(cell.toJson()));
      }
    }
  }
  // ignore: avoid_print
  if (emit) print('PERFBENCH_DONE ${cells.length}');
  return cells;
}
