import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'bench/perf_lab.dart';
import 'bench/render.dart';
import 'bench/runner.dart';
import 'bench/synthetic_docs.dart';
import 'bench/text_metrics.dart';
import 'engines/ocr_engine.dart';
import 'perf_page.dart';

/// `--dart-define=AUTORUN=full|quick|exif|one` starts the synthetic benchmark
/// on launch and prints `OCRBENCH` lines (synthetic data only) for the host.
const _autorun = String.fromEnvironment('AUTORUN');

/// `AUTORUN=perf` runs the timing matrix, `AUTORUN=acc` the accuracy guard
/// (synthetic benchmark through the experiment engines). `PERF=ort,det,...`
/// picks experiment groups (default: all).
const _perfSelect = String.fromEnvironment('PERF');

/// `AUTORUN=file`: read `mode=...` and `perf=...` lines from `autorun.txt` in
/// the app's external files directory (adb can push it), so one APK serves
/// every run on the emulator.
var _mode = _autorun;
var _select = _perfSelect;
var _spinner = true;

/// Phase 1.6b studies (`mode=study|grid|prov|best|all`) run on the Perf page;
/// `pause=<s>` shortens the rest between UI states on the emulator.
var _pauseSec = 30;
const _studyModes = {
  'study',
  'grid',
  'prov',
  'best',
  'paired',
  'langs',
  'sample',
  'all',
};
String? _samplePath;

Future<void> _readAutorunFile() async {
  final dir = await getExternalStorageDirectory();
  if (dir == null) return;
  final file = File('${dir.path}/autorun.txt');
  if (!file.existsSync()) return;
  for (final line in file.readAsLinesSync()) {
    final kv = line.split('=');
    if (kv.length != 2) continue;
    if (kv[0].trim() == 'mode') _mode = kv[1].trim();
    if (kv[0].trim() == 'perf') _select = kv[1].trim();
    if (kv[0].trim() == 'spin') _spinner = kv[1].trim() != '0';
    if (kv[0].trim() == 'pause') _pauseSec = int.tryParse(kv[1].trim()) ?? 30;
    if (kv[0].trim() == 'sample') _samplePath = kv[1].trim();
  }
}

List<PerfExperiment> get _autoExperiments {
  final wanted = _select.isEmpty ? null : _select.split(',').toSet();
  return [
    for (final e in perfExperiments)
      if (wanted == null || wanted.contains(e.group) || wanted.contains(e.id))
        e,
  ];
}

void main() {
  runApp(const SpikeApp());
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'OCR spike',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
    home: const SpikePage(),
  );
}

class _RealResult {
  _RealResult(this.engine, this.result, this.found);
  final String engine;
  final OcrResult result;
  final List<bool> found;
}

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> {
  final _values = List.generate(4, (_) => TextEditingController());
  String _lang = 'el';
  String? _imagePath;
  bool _busy = false;
  String _status = '';
  List<String> _syntheticLines = [];
  List<_RealResult> _real = [];

  @override
  void initState() {
    super.initState();
    if (_autorun.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (_autorun == 'file') await _readAutorunFile();
        if (_mode == 'perf') {
          await _runPerfAuto();
        } else if (_studyModes.contains(_mode)) {
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PerfPage(
                auto: _mode,
                pauseSec: _pauseSec,
                samplePath: _samplePath,
                select: _select.isEmpty ? null : _select.split(',').toSet(),
                cooldownSec: 0,
              ),
            ),
          );
        } else if (_mode.isNotEmpty && _mode != 'file') {
          await _runSynthetic(auto: _mode);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final c in _values) {
      c.dispose();
    }
    _deletePicked();
    super.dispose();
  }

  void _deletePicked() {
    final path = _imagePath;
    if (path != null) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty) return;
    final path = picked.first.path;
    if (path == null) return;
    _deletePicked();
    setState(() {
      _imagePath = path;
      _real = [];
    });
  }

  Future<void> _runReal() async {
    final path = _imagePath;
    if (path == null) return;
    final wanted = _values
        .map((c) => c.text.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    setState(() {
      _busy = true;
      _real = [];
    });
    final spec = DocSpec(
      id: 'real',
      type: 'real',
      lang: _lang,
      width: 0,
      font: '',
      size: 0,
      rows: const [],
      keys: const {},
    );
    for (final config in engineConfigs) {
      setState(() => _status = config.id);
      final engine = config.build(spec.lang);
      await engine.prepare();
      final result = await engine.recognize(path);
      await engine.dispose();
      final found = [for (final v in wanted) containsValue(result.text, v)];
      setState(() => _real.add(_RealResult(config.id, result, found)));
    }
    setState(() {
      _busy = false;
      _status = '';
    });
  }

  String get _realSummary {
    final b = StringBuffer('real-document summary (no text)\n');
    for (final r in _real) {
      b.writeln(
        '${r.engine}: ${r.result.elapsedMs} ms, ${r.result.text.length} chars, '
        '${r.found.where((f) => f).length}/${r.found.length} found, '
        'geometry ${r.result.hasGeometry ? "yes" : "no"}'
        '${r.result.error != null ? ", error ${r.result.error}" : ""}',
      );
    }
    return b.toString();
  }

  Future<void> _runPerfAuto() async {
    setState(() => _busy = true);
    await runPerfMatrix(
      experiments: _autoExperiments,
      progress: (m) => setState(() => _status = m),
    );
    setState(() {
      _busy = false;
      _status = 'perf done';
    });
  }

  Future<void> _runSynthetic({String auto = ''}) async {
    setState(() {
      _busy = true;
      _syntheticLines = [];
    });
    final conditions = switch (auto) {
      'quick' => [Condition.clean, Condition.rot90Exif],
      'one' => [Condition.clean],
      'exif' || 'accexif' => [Condition.rot90Exif, Condition.rot90Raw],
      'big' => [Condition.big],
      'tune' || 'acc' => [
        Condition.clean,
        Condition.rot3,
        Condition.blur,
        Condition.lowContrastNoise,
      ],
      _ => [
        for (final c in Condition.values)
          if (c != Condition.big) c,
      ],
    };
    final engines = switch (auto) {
      'exif' => exifConfigs,
      'tune' => tuningConfigs,
      'acc' || 'accexif' => [
        for (final e in _autoExperiments)
          EngineConfig('paddle_${e.id}', (l) => e.build(paddleKeyFor(l))),
      ],
      _ => engineConfigs,
    };
    final started = DateTime.now();
    final records = await runSynthetic(
      conditions: conditions,
      engines: engines,
      progress: (m) => setState(() => _status = m),
      emit: true,
    );
    final total = DateTime.now().difference(started);
    setState(() {
      _busy = false;
      _status = 'done in ${total.inSeconds} s';
      _syntheticLines = [for (final s in summarize(records).values) s.line];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR spike (synthetic + real)'),
        actions: [
          TextButton(
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const PerfPage()),
                  ),
            child: const Text('Perf'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton(
            onPressed: _busy ? null : () => _runSynthetic(),
            child: const Text('Run synthetic'),
          ),
          if (_syntheticLines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_syntheticLines.join('\n')),
            ),
          const Divider(height: 32),
          const Text('Real document (values stay in memory only)'),
          Row(
            children: [
              const Text('Language '),
              DropdownButton<String>(
                value: _lang,
                items: const [
                  DropdownMenuItem(value: 'el', child: Text('el+en')),
                  DropdownMenuItem(value: 'es', child: Text('es+en')),
                  DropdownMenuItem(value: 'ru', child: Text('ru+en')),
                ],
                onChanged: _busy ? null : (v) => setState(() => _lang = v!),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: _busy ? null : _pick,
                child: const Text('Pick image'),
              ),
            ],
          ),
          Text(_imagePath == null ? 'no image' : 'image selected'),
          for (var i = 0; i < _values.length; i++)
            TextField(
              controller: _values[i],
              decoration: InputDecoration(labelText: 'Known value ${i + 1}'),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy || _imagePath == null ? null : _runReal,
            child: const Text('Run'),
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  if (_spinner)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  const SizedBox(width: 12),
                  Expanded(child: Text('working: $_status')),
                ],
              ),
            ),
          for (final r in _real) _realTile(r),
          if (_real.isNotEmpty)
            TextButton(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: _realSummary)),
              child: const Text('Copy summary'),
            ),
          if (!_busy && _status.isNotEmpty) Text(_status),
        ],
      ),
    );
  }

  Widget _realTile(_RealResult r) {
    final marks = r.found.map((f) => f ? '✓' : '✗').join(' ');
    final res = r.result;
    return ExpansionTile(
      title: Text('${r.engine}   $marks'),
      subtitle: Text(
        '${res.elapsedMs} ms · ${res.text.length} chars · '
        'conf ${res.confidence == null ? "–" : res.confidence!.toStringAsFixed(2)} · '
        'geometry ${res.hasGeometry ? "yes (${res.lines.length})" : "no"}'
        '${res.error != null ? " · error ${res.error}" : ""}',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SelectableText(res.text),
        ),
      ],
    );
  }
}
