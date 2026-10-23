import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bench/device_info.dart';
import 'bench/lang_bench.dart';
import 'bench/perf_lab.dart';
import 'bench/perf_scenarios.dart';
import 'bench/perf_study.dart';
import 'bench/run_log.dart';
import 'engines/paddle/paddle_config.dart';

/// Phase 1.6 / 1.6b / 1.6c: timing breakdown of the Paddle pipeline and the
/// controlled phone studies (UI load A/B, provider x threads grid, provider
/// accuracy, "best" preset, paired A/B, language packs). Cold = sessions
/// loaded from scratch plus the first run; warm = mean of the runs after one
/// settling run. Only numbers are shown and copied; nothing from a picked
/// image is read out, logged or stored.
///
/// Every cell is written to a small log in the app's own directory before it
/// runs and after it finishes, so a run cut by the system is reported at the
/// next start and can be resumed.
class PerfPage extends StatefulWidget {
  /// [auto] (`study`, `grid`, `prov`, `best`, `paired`, `langs`, `all`,
  /// `sample`) starts that action after the first frame (emulator runs driven
  /// from `autorun.txt`). `sample` runs the experiments in [select] on the
  /// file [samplePath].
  const PerfPage({
    super.key,
    this.auto,
    this.pauseSec = 30,
    this.samplePath,
    this.select,
    this.cooldownSec = 20,
  });

  final String? auto;
  final int pauseSec;
  final String? samplePath;
  final Set<String>? select;
  final int cooldownSec;

  @override
  State<PerfPage> createState() => _PerfPageState();
}

/// The spinner whose workload is the "UI load" of the studies.
class UiLoadIndicator extends StatefulWidget {
  const UiLoadIndicator({super.key});

  @override
  State<UiLoadIndicator> createState() => _UiLoadIndicatorState();
}

class _UiLoadIndicatorState extends State<UiLoadIndicator> {
  Timer? _timer;
  var _on = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (uiLoad.value == UiLoad.low) setState(() => _on = !_on);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<UiLoad>(
    valueListenable: uiLoad,
    builder: (_, mode, _) => SizedBox(
      width: 24,
      height: 24,
      child: switch (mode) {
        UiLoad.max => const CircularProgressIndicator(strokeWidth: 3),
        UiLoad.still => const Icon(Icons.pause_circle_outline, size: 24),
        UiLoad.low => Icon(
          _on ? Icons.circle : Icons.circle_outlined,
          size: 24,
        ),
      },
    ),
  );
}

class _PerfPageState extends State<PerfPage> {
  final _groups = <String>{'baseline', 'final'};
  var _camera = true;
  var _busy = false;
  var _status = '';
  final _cells = <PerfCell>[];
  final _lines = <String>[];
  String? _pickedHard, _pickedReceipt;
  late int _cooldown = widget.cooldownSec;

  RunLog? _log;
  var _saved = RunLogState();
  var _exits = <ExitInfo>[];

  // Results the later steps build on (kept in memory for this session).
  final _gridPoints = <GridPoint>[];
  Set<String> _excluded = {};
  ({PaddleConfig config, String label}) _best = provisionalBest;

  List<PerfExperiment> get _selected => [
    for (final e in perfExperiments)
      if (widget.select != null
          ? (widget.select!.contains(e.id) || widget.select!.contains(e.group))
          : _groups.contains(e.group))
        if (_camera)
          e
        else
          PerfExperiment(
            e.id,
            e.group,
            e.title,
            e.config,
            sizes: const [PhotoSize.native],
          ),
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final log = await RunLog.open();
    final state = log.read();
    final exits = await exitReasons();
    if (!mounted) return;
    setState(() {
      _log = log;
      _saved = state;
      _exits = exits;
      _lines.addAll(state.lines);
    });
    final auto = widget.auto;
    if (auto == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      switch (auto) {
        case 'study':
          await _runStudy();
        case 'grid':
          await _runGrid();
        case 'prov':
          await _runProv();
        case 'best':
          await _runBest();
        case 'paired':
          await _runPaired();
        case 'langs':
          await _runLangs();
        case 'sample':
          _pickedHard = widget.samplePath;
          await _runPicked();
        case 'all':
          await _runStudy();
          await _runGrid();
          await _runProv();
          await _runBest();
      }
    });
  }

  // ------------------------------------------------------------ plumbing

  /// A line produced by a study or by this page: shown, printed for the host
  /// and saved in the log.
  void _line(String l) {
    // ignore: avoid_print
    print('PERFSTUDY $l');
    _log?.note(l);
    if (mounted) setState(() => _lines.add(l));
  }

  void _note(String l) => _line(l);

  void _progress(String m) {
    if (mounted) setState(() => _status = m);
  }

  Future<void> _guard(
    String plan,
    Map<String, Object?> params,
    Future<void> Function() body, {
    bool resume = false,
  }) async {
    setState(() => _busy = true);
    await keepAwake(true);
    try {
      if (!resume) await _log?.plan(plan, params);
      final t0 = await batteryTempC();
      await body();
      final t1 = await batteryTempC();
      _note('T plan $plan: battery ${tempText(t0)} -> ${tempText(t1)} C');
      await _log?.finish(plan);
      // ignore: avoid_print
      print('PERFSTUDY_DONE');
      if (mounted) setState(() => _status = 'done');
    } catch (e, st) {
      // ignore: avoid_print
      print('PERFSTUDY ERROR in plan $plan: ${e.runtimeType} $e\n$st');
      _line('ERROR in plan $plan: ${e.runtimeType} (see the stack in logcat)');
      if (mounted) setState(() => _status = 'error ${e.runtimeType}');
    } finally {
      await keepAwake(false);
      if (_log != null && mounted) {
        setState(() {
          _saved = _log!.read();
          _busy = false;
        });
      }
    }
  }

  CellHooks _hooks(Set<String> done) => CellHooks(
    done: done,
    begin: (id) async => _log?.begin(id),
    end: (id, cell) async {
      // ignore: avoid_print
      print('PERFSTUDY ${cell.line}');
      await _log?.end(id, cell.toJson());
    },
    note: _line,
    cooldownSec: _cooldown,
  );

  Set<String> _doneIds(bool resume) => resume ? _saved.done.keys.toSet() : {};

  Map<String, String> get _pickedSamples => {
    'your_receipt': ?_pickedReceipt,
    'your_hard_sample': ?_pickedHard,
  };

  Future<String?> _pickFile() async {
    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty) return null;
    return picked.first.path;
  }

  /// The experiments on the user's picked images, one cell per
  /// (experiment, sample); the sample guard decides what is allowed.
  Future<void> _pickedCells(List<PerfExperiment> exps, Set<String> done) async {
    String? previous;
    for (final s in _pickedSamples.entries) {
      for (final exp in exps) {
        final id = '${exp.id}/${s.key}';
        if (done.contains(id)) continue;
        await groupBoundary(_hooks(done), previous, exp.group, _progress);
        previous = exp.group;
        _progress('${exp.id} (${s.key})');
        await _log?.begin(id);
        final cell = await runPerfCell(
          exp: exp,
          scenarioId: s.key,
          size: PhotoSize.native,
          image: File(s.value),
        );
        await _log?.end(id, cell.toJson());
        // ignore: avoid_print
        print('PERFSTUDY ${cell.line}');
        if (mounted) setState(() => _cells.add(cell));
      }
    }
  }

  // ------------------------------------------------------------- the steps

  Future<void> _run({bool resume = false}) => _guard(
    'matrix',
    {'groups': _groups.toList(), 'camera': _camera},
    () async {
      await runPerfMatrix(
        experiments: _selected,
        progress: _progress,
        onCell: (c) => setState(() => _cells.add(c)),
        hooks: _hooks(_doneIds(resume)),
      );
    },
    resume: resume,
  );

  Future<void> _runPicked({bool resume = false}) => _guard(
    'picked',
    {'groups': _groups.toList()},
    () => _pickedCells(_selected, _doneIds(resume)),
    resume: resume,
  );

  Future<File> _studyImage() async {
    final path = _pickedReceipt ?? _pickedHard;
    if (path != null) return File(path);
    return buildScenarioImage(
      perfScenarios.first,
      PhotoSize.camera,
      await perfImageDir(),
    );
  }

  String get _studyImageLabel => _pickedReceipt != null
      ? 'your receipt'
      : _pickedHard != null
      ? 'your hard sample'
      : 'synthetic receipt 12 MP';

  Future<void> _runStudy() => _guard('study', {}, () async {
    await runUiLoadStudy(
      image: await _studyImage(),
      imageLabel: _studyImageLabel,
      pauseSec: widget.pauseSec,
      progress: _progress,
      out: _line,
    );
  });

  Future<void> _runGrid({
    bool resume = false,
  }) => _guard('grid', {'passes': 2}, () async {
    final done = _doneIds(resume);
    _gridPoints.clear();
    if (resume) {
      for (final e in _saved.done.entries) {
        if (e.key.startsWith('g_')) {
          _gridPoints.add(GridPoint.fromJson(e.value, e.key.split('/').last));
        }
      }
    }
    _note(
      'B: provider x threads, two passes (forward, then backwards). '
      '${await envLine()}; ${await providersLine()}; '
      'UI load ${uiLoad.value.name}; rest $_cooldown s between passes',
    );
    final forward = buildGridExperiments();
    for (final pass in ['p1', 'p2']) {
      final order = pass == 'p1' ? forward : forward.reversed.toList();
      final cells = await runPerfMatrix(
        experiments: order,
        progress: _progress,
        onCell: (c) => setState(() => _cells.add(c)),
        lightJank: true,
        tag: pass,
        hooks: _hooks(done),
      );
      _gridPoints.addAll([for (final c in cells) GridPoint.fromCell(c, pass)]);
      if (_cooldown > 0 && pass == 'p1') {
        for (var s = _cooldown; s > 0; s--) {
          _progress('rest $s s before pass 2');
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
    }
    _note(
      'B means (mean warm ms over 3 scenarios and 2 passes; noise between '
      'passes ${(100 * gridNoise(_gridPoints)).toStringAsFixed(1)}%, margin to '
      'leave the CPU 4-thread cell ${(100 * gridMargin(_gridPoints)).toStringAsFixed(1)}%):',
    );
    for (final e in gridMeans(_gridPoints).entries) {
      _note('B ${e.key}: ${e.value.round()} ms');
    }
    _best = chooseBest(_gridPoints, _excluded);
    _note('B best so far: ${_best.label}');
  }, resume: resume);

  Future<Map<String, File>> _accuracyImages() async {
    final dir = await perfImageDir();
    return {
      for (final s in perfScenarios)
        s.id: await buildScenarioImage(s, PhotoSize.native, dir),
      for (final e in _pickedSamples.entries) e.key: File(e.value),
    };
  }

  Future<void> _runProv() => _guard('prov', {}, () async {
    final outcome = await runProviderAccuracy(
      images: await _accuracyImages(),
      threads: _best.config.threads,
      progress: _progress,
      out: _line,
    );
    _excluded = outcome.excluded;
    if (_gridPoints.isNotEmpty) _best = chooseBest(_gridPoints, _excluded);
    _note(
      'C providers excluded from "best": '
      '${_excluded.isEmpty ? 'none' : _excluded.join(', ')}',
    );
  });

  Future<void> _runBest({bool resume = false}) => _guard('best', {}, () async {
    _note('D: best = ${_best.label}');
    _note('D: setting ${describeConfig(_best.config)}; ${await envLine()}');
    final exp = PerfExperiment(
      'best',
      'best',
      'best setting',
      _best.config,
      sizes: const [PhotoSize.native, PhotoSize.camera],
    );
    final done = _doneIds(resume);
    await runPerfMatrix(
      experiments: [exp],
      progress: _progress,
      onCell: (c) => setState(() => _cells.add(c)),
      hooks: _hooks(done),
    );
    await _pickedCells([exp], done);
  }, resume: resume);

  Future<void> _runPaired() => _guard('paired', {}, () async {
    final image = await _studyImage();
    _note(
      'F: paired A/B (A B | B A | ...) on $_studyImageLabel. '
      '${await envLine()}; UI load ${uiLoad.value.name}',
    );
    final comparisons = <(String, PaddleConfig, PaddleConfig?, int, int)>[
      ('control: same setting twice', studyConfig, null, 1, 1),
      ('batch 1 against batch 4', studyConfig, null, 1, 4),
      ('batch 1 against batch 2', studyConfig, null, 1, 2),
      (
        'ArgMax model off (A) against on (B)',
        studyConfig.copyWith(recArgmax: false),
        studyConfig,
        1,
        1,
      ),
      (
        'engine in the root isolate (A) against background isolate (B)',
        studyConfig.copyWith(isolate: false),
        studyConfig,
        1,
        1,
      ),
      (
        'Phase 1.5 pipeline (A) against study setting (B)',
        const PaddleConfig(),
        studyConfig,
        1,
        1,
      ),
    ];
    for (final c in comparisons) {
      await runPairedAB(
        name: c.$1,
        config: c.$2,
        configB: c.$3,
        batchA: c.$4,
        batchB: c.$5,
        image: image,
        progress: _progress,
        out: _line,
      );
    }
  });

  Future<void> _runLangs() => _guard('langs', {}, () async {
    await runLangPackBench(progress: _progress, out: _line);
  });

  Future<void> _resume() async {
    final plan = _saved.planName;
    if (plan == null) return;
    final g = (_saved.planParams['groups'] as List?)?.cast<String>();
    if (g != null) {
      setState(() {
        _groups
          ..clear()
          ..addAll(g);
        _camera = (_saved.planParams['camera'] as bool?) ?? _camera;
      });
    }
    switch (plan) {
      case 'matrix':
        await _run(resume: true);
      case 'picked':
        await _runPicked(resume: true);
      case 'grid':
        await _runGrid(resume: true);
      case 'best':
        await _runBest(resume: true);
    }
  }

  bool get _canResume =>
      _saved.wasCut &&
      const {'matrix', 'picked', 'grid', 'best'}.contains(_saved.planName);

  Future<void> _clearAll() async {
    await _log?.clear();
    setState(() {
      _cells.clear();
      _lines.clear();
      _status = '';
      _saved = RunLogState();
    });
  }

  String get _summary =>
      'perf summary (numbers only), UI load ${uiLoad.value.name}, '
      'display ${displayRefreshRate()?.toStringAsFixed(0) ?? 'n/a'} Hz, '
      'device $deviceTag\n'
      '${_exits.isEmpty ? '' : 'previous process exits (Android): ${_exits.take(3).map((e) => e.line).join(' | ')}\n'}'
      '${(_log?.read().lines ?? _lines).join('\n')}';

  // ------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(fontFamily: 'NotoSansMono', fontSize: 11);
    return Scaffold(
      appBar: AppBar(title: const Text('Phase 1.6c: performance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_saved.wasCut && !_busy)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_saved.cutText),
                    if (_exits.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Android says the last process ended: ${_exits.first.line}',
                          style: mono,
                        ),
                      ),
                    const Text(
                      'Saved results are in the list below and in Copy summary.',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton(
                          onPressed: _canResume ? _resume : null,
                          child: const Text('Resume'),
                        ),
                        TextButton(
                          onPressed: () async {
                            await _log?.finish(_saved.planName ?? '');
                            setState(() => _saved = _log!.read());
                          },
                          child: const Text('Dismiss'),
                        ),
                      ],
                    ),
                    if (!_canResume)
                      const Text(
                        'This step has no cell-by-cell resume: run it again.',
                      ),
                  ],
                ),
              ),
            ),
          const Row(
            children: [
              UiLoadIndicator(),
              SizedBox(width: 12),
              Expanded(child: Text('UI load while a run is going:')),
            ],
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<UiLoad>(
            valueListenable: uiLoad,
            builder: (_, mode, _) => SegmentedButton<UiLoad>(
              segments: const [
                ButtonSegment(value: UiLoad.max, label: Text('max')),
                ButtonSegment(value: UiLoad.still, label: Text('still')),
                ButtonSegment(value: UiLoad.low, label: Text('1 fr/s')),
              ],
              selected: {mode},
              onSelectionChanged: _busy ? null : (s) => uiLoad.value = s.first,
            ),
          ),
          Row(
            children: [
              const Text('Rest between groups '),
              DropdownButton<int>(
                value: _cooldown,
                items: const [
                  DropdownMenuItem(value: 0, child: Text('none')),
                  DropdownMenuItem(value: 20, child: Text('20 s')),
                  DropdownMenuItem(value: 30, child: Text('30 s')),
                ],
                onChanged: _busy ? null : (v) => setState(() => _cooldown = v!),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Display ${displayRefreshRate()?.toStringAsFixed(0) ?? 'n/a'} Hz. '
              'The screen is kept on while a step runs.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const Divider(),
          Wrap(
            spacing: 8,
            children: [
              for (final g in perfGroups)
                FilterChip(
                  label: Text(g),
                  selected: _groups.contains(g),
                  onSelected: _busy
                      ? null
                      : (v) => setState(
                          () => v ? _groups.add(g) : _groups.remove(g),
                        ),
                ),
            ],
          ),
          CheckboxListTile(
            value: _camera,
            onChanged: _busy ? null : (v) => setState(() => _camera = v!),
            title: const Text('Also 12 MP photo-size images'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          FilledButton(
            onPressed: _busy || _groups.isEmpty ? null : _run,
            child: const Text('Run synthetic scenarios'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final p = await _pickFile();
                        if (p != null) setState(() => _pickedReceipt = p);
                      },
                child: const Text('Pick your receipt'),
              ),
              const SizedBox(width: 8),
              Text(_pickedReceipt == null ? 'none' : 'selected'),
            ],
          ),
          Row(
            children: [
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final p = await _pickFile();
                        if (p != null) setState(() => _pickedHard = p);
                      },
                child: const Text('Pick your hard sample'),
              ),
              const SizedBox(width: 8),
              Text(_pickedHard == null ? 'none' : 'selected'),
              const Spacer(),
              FilledButton.tonal(
                onPressed:
                    _busy ||
                        _groups.isEmpty ||
                        (_pickedHard == null && _pickedReceipt == null)
                    ? null
                    : _runPicked,
                child: const Text('Run on them'),
              ),
            ],
          ),
          const Divider(height: 32),
          const Text('Phase 1.6b/c (rested, cold phone, no charger; in order)'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _busy ? null : _runStudy,
                child: const Text('A: UI load A/B'),
              ),
              FilledButton(
                onPressed: _busy ? null : _runGrid,
                child: const Text('B: provider x threads'),
              ),
              FilledButton(
                onPressed: _busy ? null : _runProv,
                child: const Text('C: provider accuracy'),
              ),
              FilledButton(
                onPressed: _busy ? null : _runBest,
                child: const Text('D: best'),
              ),
              FilledButton.tonal(
                onPressed: _busy ? null : _runPaired,
                child: const Text('F: paired A/B'),
              ),
              FilledButton.tonal(
                onPressed: _busy ? null : _runLangs,
                child: const Text('G: language packs'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'best = ${_best.label}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('working: $_status'),
            ),
          if (!_busy && _status.isNotEmpty) Text(_status),
          for (final l in _lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(l, style: mono),
            ),
          for (final c in _cells)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(c.line, style: mono),
            ),
          if (_cells.isNotEmpty || _lines.isNotEmpty)
            Row(
              children: [
                TextButton(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _summary)),
                  child: const Text('Copy summary'),
                ),
                TextButton(
                  onPressed: _busy ? null : _clearAll,
                  child: const Text('Clear'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
