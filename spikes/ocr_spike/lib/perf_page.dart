import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bench/perf_lab.dart';
import 'bench/perf_scenarios.dart';
import 'bench/perf_study.dart';
import 'engines/paddle/paddle_config.dart';

/// Phase 1.6 / 1.6b: timing breakdown of the Paddle pipeline and the
/// controlled phone studies (UI load A/B, provider x threads grid, provider
/// accuracy, "best" preset). Cold = sessions loaded from scratch plus the
/// first run; warm = mean of the 3 following runs. Only numbers are shown and
/// copied; nothing from a picked image is read out, logged or stored.
class PerfPage extends StatefulWidget {
  /// [auto] (`study`, `grid`, `prov`, `best`) starts that action after the
  /// first frame (emulator runs driven from `autorun.txt`).
  const PerfPage({super.key, this.auto, this.pauseSec = 30});

  final String? auto;
  final int pauseSec;

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

  // Results the later steps build on (kept in memory for this session).
  final _gridCells = <PerfCell>[];
  Set<String> _excluded = {};
  ({PaddleConfig config, String label}) _best = provisionalBest;

  List<PerfExperiment> get _selected => [
    for (final e in perfExperiments)
      if (_groups.contains(e.group))
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
    final auto = widget.auto;
    if (auto != null) {
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
          case 'all':
            await _runStudy();
            await _runGrid();
            await _runProv();
            await _runBest();
        }
      });
    }
  }

  Future<void> _guard(Future<void> Function() body) async {
    setState(() => _busy = true);
    try {
      await body();
      // ignore: avoid_print
      print('PERFSTUDY_DONE');
      setState(() => _status = 'done');
    } catch (e) {
      setState(() => _status = 'error ${e.runtimeType}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _line(String l) {
    if (mounted) setState(() => _lines.add(l));
  }

  /// A line made by this page (the studies print their own).
  void _note(String l) {
    // ignore: avoid_print
    print('PERFSTUDY $l');
    _line(l);
  }

  void _progress(String m) {
    if (mounted) setState(() => _status = m);
  }

  Future<void> _run() => _guard(() async {
    await runPerfMatrix(
      experiments: _selected,
      progress: _progress,
      onCell: (c) => setState(() => _cells.add(c)),
    );
  });

  Future<String?> _pickFile() async {
    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty) return null;
    return picked.first.path;
  }

  Future<void> _runPicked() => _guard(() async {
    final samples = _pickedSamples;
    for (final s in samples.entries) {
      for (final exp in _selected) {
        _progress('${exp.id} (${s.key})');
        final cell = await runPerfCell(
          exp: exp,
          scenarioId: s.key,
          size: PhotoSize.native,
          image: File(s.value),
        );
        setState(() => _cells.add(cell));
      }
    }
  });

  Map<String, String> get _pickedSamples => {
    'your_receipt': ?_pickedReceipt,
    'your_hard_sample': ?_pickedHard,
  };

  // ------------------------------------------------------------------- A..D

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

  Future<void> _runStudy() => _guard(() async {
    await runUiLoadStudy(
      image: await _studyImage(),
      imageLabel: _studyImageLabel,
      pauseSec: widget.pauseSec,
      progress: _progress,
      out: _line,
    );
  });

  Future<void> _runGrid() => _guard(() async {
    _note(
      'B: provider x threads. ${envLine()}; ${await providersLine()}; '
      'UI load ${uiLoad.value.name}',
    );
    _gridCells.clear();
    final cells = await runPerfMatrix(
      experiments: buildGridExperiments(),
      progress: _progress,
      onCell: (c) => setState(() => _cells.add(c)),
      lightJank: true,
    );
    _gridCells.addAll(cells);
    _note(
      'B means (mean warm ms over the 3 scenarios; margin to leave the CPU '
      '4-thread cell ${(100 * gridMargin(gridMeans(cells))).toStringAsFixed(1)}%):',
    );
    for (final e in gridMeans(cells).entries) {
      _note('B ${e.key}: ${e.value.round()} ms');
    }
    _best = chooseBest(_gridCells, _excluded);
    _note('B best so far: ${_best.label}');
  });

  Future<Map<String, File>> _accuracyImages() async {
    final dir = await perfImageDir();
    return {
      for (final s in perfScenarios)
        s.id: await buildScenarioImage(s, PhotoSize.native, dir),
      if (_pickedReceipt != null) 'your_receipt': File(_pickedReceipt!),
      if (_pickedHard != null) 'your_hard_sample': File(_pickedHard!),
    };
  }

  Future<void> _runProv() => _guard(() async {
    final threads = _best.config.threads;
    final outcome = await runProviderAccuracy(
      images: await _accuracyImages(),
      threads: threads,
      progress: _progress,
      out: _line,
    );
    _excluded = outcome.excluded;
    if (_gridCells.isNotEmpty) {
      _best = chooseBest(_gridCells, _excluded);
    }
    _note(
      'C providers excluded from "best": '
      '${_excluded.isEmpty ? 'none' : _excluded.join(', ')}',
    );
  });

  Future<void> _runBest() => _guard(() async {
    _note('D: best = ${_best.label}');
    _note('D: setting ${describeConfig(_best.config)}; ${envLine()}');
    final exp = PerfExperiment(
      'best',
      'best',
      'best setting',
      _best.config,
      sizes: const [PhotoSize.native, PhotoSize.camera],
    );
    await runPerfMatrix(
      experiments: [exp],
      progress: _progress,
      onCell: (c) => setState(() => _cells.add(c)),
    );
    final samples = _pickedSamples;
    for (final s in samples.entries) {
      _progress('best (${s.key})');
      final cell = await runPerfCell(
        exp: exp,
        scenarioId: s.key,
        size: PhotoSize.native,
        image: File(s.value),
      );
      setState(() => _cells.add(cell));
    }
  });

  String get _summary =>
      'perf summary (numbers only), ${envLine()}, UI load ${uiLoad.value.name}\n'
      '${_lines.join('\n')}${_lines.isEmpty ? '' : '\n'}'
      '${_cells.map((c) => c.line).join('\n')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Phase 1.6b: performance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const UiLoadIndicator(),
              const SizedBox(width: 12),
              const Expanded(child: Text('UI load while a run is going:')),
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Display ${displayRefreshRate()?.toStringAsFixed(0) ?? 'n/a'} Hz. '
              'Set the screen timeout to 10 minutes or more first.',
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
                    _busy || (_pickedHard == null && _pickedReceipt == null)
                    ? null
                    : _runPicked,
                child: const Text('Run on them'),
              ),
            ],
          ),
          const Divider(height: 32),
          const Text('Phase 1.6b (rested, cold phone, no charger; in order)'),
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
              child: Text(
                l,
                style: const TextStyle(
                  fontFamily: 'NotoSansMono',
                  fontSize: 11,
                ),
              ),
            ),
          for (final c in _cells)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                c.line,
                style: const TextStyle(
                  fontFamily: 'NotoSansMono',
                  fontSize: 11,
                ),
              ),
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
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _cells.clear();
                          _lines.clear();
                          _status = '';
                        }),
                  child: const Text('Clear'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
