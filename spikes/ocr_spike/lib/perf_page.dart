import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bench/perf_lab.dart';
import 'bench/perf_scenarios.dart';

/// Phase 1.6: timing breakdown of the Paddle pipeline. Cold = sessions loaded
/// from scratch plus the first run; warm = mean of the 3 following runs.
/// Only numbers are shown and copied; nothing from a picked image is read
/// out, logged or stored.
class PerfPage extends StatefulWidget {
  const PerfPage({super.key});

  @override
  State<PerfPage> createState() => _PerfPageState();
}

class _PerfPageState extends State<PerfPage> {
  final _groups = <String>{'baseline', 'final'};
  var _camera = true;
  var _busy = false;
  var _status = '';
  final _cells = <PerfCell>[];
  String? _picked;

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

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _cells.clear();
    });
    await runPerfMatrix(
      experiments: _selected,
      progress: (m) => setState(() => _status = m),
      onCell: (c) => setState(() => _cells.add(c)),
    );
    setState(() {
      _busy = false;
      _status = 'done';
    });
  }

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty) return;
    setState(() => _picked = picked.first.path);
  }

  Future<void> _runPicked() async {
    final path = _picked;
    if (path == null) return;
    setState(() {
      _busy = true;
      _cells.clear();
    });
    for (final exp in _selected) {
      setState(() => _status = '${exp.id} (your image)');
      final cell = await runPerfCell(
        exp: exp,
        scenarioId: 'real',
        size: PhotoSize.native,
        image: File(path),
      );
      setState(() => _cells.add(cell));
    }
    setState(() {
      _busy = false;
      _status = 'done';
    });
  }

  String get _summary =>
      'perf summary (numbers only), device tag $deviceTag\n'
      '${_cells.map((c) => c.line).join('\n')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Phase 1.6: performance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Always spinning: a stutter here means UI jank.'),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                onPressed: _busy ? null : _pick,
                child: const Text('Pick your hard sample'),
              ),
              const SizedBox(width: 8),
              Text(_picked == null ? 'none' : 'selected'),
              const Spacer(),
              FilledButton.tonal(
                onPressed: _busy || _picked == null ? null : _runPicked,
                child: const Text('Run on it'),
              ),
            ],
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('working: $_status'),
            ),
          if (!_busy && _status.isNotEmpty) Text(_status),
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
          if (_cells.isNotEmpty)
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: _summary)),
              child: const Text('Copy summary'),
            ),
        ],
      ),
    );
  }
}
