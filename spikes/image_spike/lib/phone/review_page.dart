import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'ocr_service.dart';
import 'pipeline.dart';
import 'verdicts.dart';

/// The situations of the phone check (the table in docs/PHASE_6_0_VALIDATION.md).
const situations = [
  'Καλά φωτισμένο έγγραφο',
  'Κακοφωτισμένο έγγραφο',
  'Τσαλακωμένη απόδειξη',
  'Κεκλιμένο έγγραφο',
  'Έγγραφο σε σκούρο φόντο',
  'Έγγραφο εκτός καρέ (κομμένο)',
  'Μικρή απόδειξη σε μεγάλο τραπέζι',
  'Άλλο',
];

/// Shows each picked photo as "original | after" and asks one question: is the
/// right side a good page for the PDF? Nothing is stored or sent except the
/// numbers and the answers (VerdictStore).
class ReviewPage extends StatefulWidget {
  const ReviewPage({
    super.key,
    required this.paths,
    required this.engine,
    required this.store,
    required this.ocr,
    this.process = processPhoto,
  });

  final List<String> paths;
  final Engine engine;
  final VerdictStore store;
  final SpikeOcr? ocr;
  final Future<PhotoResult> Function(String path, Engine engine) process;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  var _index = 0;
  PhotoResult? _result;
  Object? _error;
  var _flat = false;
  var _label = situations.first;
  var _busyOcr = false;
  OcrNumbers? _before;
  OcrNumbers? _after;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _result = null;
      _error = null;
      _flat = false;
      _before = null;
      _after = null;
    });
    try {
      final r = await widget.process(widget.paths[_index], widget.engine);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _measureOcr() async {
    final ocr = widget.ocr;
    final r = _result;
    if (ocr == null || r == null) return;
    setState(() => _busyOcr = true);
    final a = ocr.writeTemp(r.frameJpg), b = ocr.writeTemp(_afterBytes(r));
    try {
      final before = await ocr.readFile(
        a,
        width: r.frameWidth,
        height: r.frameHeight,
      );
      final after = await ocr.readFile(
        b,
        width: r.frameWidth,
        height: r.frameHeight,
      );
      if (mounted) {
        setState(() {
          _before = before;
          _after = after;
        });
      }
    } finally {
      a.deleteSync();
      b.deleteSync();
      if (mounted) setState(() => _busyOcr = false);
    }
  }

  Uint8List _afterBytes(PhotoResult r) => _flat ? r.afterFlatJpg : r.afterJpg;

  void _answer(bool good) {
    final r = _result;
    if (r == null) return;
    widget.store.verdicts.add(
      Verdict(
          n: widget.store.verdicts.length + 1,
          label: _label,
          engine: widget.engine.label,
          score: r.score,
          used: r.used,
          good: good,
          detectMs: r.detectMs,
          warpMs: r.warpMs,
          sourceMp: r.sourceWidth * r.sourceHeight / 1e6,
        )
        ..wordsBefore = _before?.words
        ..wordsAfter = _after?.words
        ..ocrMsBefore = _before?.ms
        ..ocrMsAfter = _after?.ms,
    );
    if (_index + 1 < widget.paths.length) {
      _index++;
      _load();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      appBar: AppBar(
        title: Text('Φωτογραφία ${_index + 1} από ${widget.paths.length}'),
      ),
      body: _error != null
          ? Center(child: Text('Δεν διαβάστηκε η φωτογραφία: $_error'))
          : r == null
          ? const Center(child: CircularProgressIndicator())
          : _body(r),
    );
  }

  Widget _body(PhotoResult r) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        DropdownButton<String>(
          value: _label,
          isExpanded: true,
          items: [
            for (final s in situations)
              DropdownMenuItem(value: s, child: Text(s)),
          ],
          onChanged: (v) => setState(() => _label = v!),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _pane('Πρωτότυπο', r.frameJpg)),
            const SizedBox(width: 8),
            Expanded(
              child: _pane(
                r.used ? 'Μετά (κομμένο)' : 'Μετά (ολόκληρο καρέ)',
                _afterBytes(r),
              ),
            ),
          ],
        ),
        SwitchListTile(
          title: const Text('Με αφαίρεση σκιάς (δεξιά εικόνα)'),
          value: _flat,
          onChanged: (v) => setState(() => _flat = v),
        ),
        Text(
          r.used
              ? 'Η ανίχνευση είναι σίγουρη (${r.score.toStringAsFixed(2)}): το PDF θα έπαιρνε το κομμένο.'
              : 'Η ανίχνευση δεν είναι σίγουρη (${r.score.toStringAsFixed(2)}): το PDF θα έπαιρνε ολόκληρο το καρέ.',
          style: TextStyle(color: r.used ? scheme.primary : scheme.error),
        ),
        Text(
          '${widget.engine.label}: ανίχνευση ${r.detectMs} ms, μετασχηματισμός ${r.warpMs} ms · '
          'αρχείο ${(r.sourceWidth * r.sourceHeight / 1e6).toStringAsFixed(1)} MP · '
          'εστιακή ${r.focalPx > 0 ? 'από EXIF' : 'άγνωστη'} · '
          'η άλλη μέθοδος: ${r.otherScore.toStringAsFixed(2)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (widget.ocr != null) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busyOcr ? null : _measureOcr,
            child: Text(_busyOcr ? 'Μέτρηση…' : 'Μέτρηση OCR (μόνο αριθμοί)'),
          ),
          if (_before != null && _after != null)
            Text(
              'Λέξεις: πρωτότυπο ${_before!.words} (${_before!.ms} ms) · '
              'μετά ${_after!.words} (${_after!.ms} ms)',
            ),
        ],
        const SizedBox(height: 16),
        Text(
          'Είναι η δεξιά εικόνα σωστή σελίδα για το PDF;',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: () => _answer(true),
                child: const Text('ΝΑΙ'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.tonal(
                onPressed: () => _answer(false),
                child: const Text('ΟΧΙ'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _pane(String title, Uint8List jpg) {
    return Column(
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Image.memory(jpg, fit: BoxFit.contain, gaplessPlayback: true),
        ),
      ],
    );
  }
}
