import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'background_runner.dart';
import 'ocr_service.dart';
import 'pipeline.dart';

/// The background test (request 5): pages arrive like the shots of a Multi
/// Page scan and are prepared and read behind the screen. It runs the scan
/// twice, as the app does today (OCR only) and with the crop step, and shows
/// the wait after the last shot and the frames of this screen that were slow.
class BackgroundPage extends StatefulWidget {
  const BackgroundPage({
    super.key,
    required this.pages,
    required this.engine,
    required this.ocr,
  });

  final int pages;
  final Engine engine;
  final SpikeOcr? ocr;

  @override
  State<BackgroundPage> createState() => _BackgroundPageState();
}

class _BackgroundPageState extends State<BackgroundPage> {
  var _intervalMs = 2500;
  var _running = false;
  var _status = '';
  final _reports = <BackgroundReport>[];

  Future<List<Uint8List>> _load() async {
    final manifest = (jsonDecode(
      await rootBundle.loadString('assets/eval_full/manifest.json'),
    ) as List).cast<Map<String, Object?>>();
    final ids = [
      for (final e in manifest)
        if (e['truth'] != null &&
            e['partial'] == false &&
            e['fillsFrame'] == false)
          e['id']! as String,
    ];
    return [
      for (var i = 0; i < widget.pages; i++)
        (await rootBundle.load('assets/eval_full/${ids[i % ids.length]}.jpg'))
            .buffer
            .asUint8List(),
    ];
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _reports.clear();
    });
    final jpegs = await _load();
    for (final straighten in [false, true]) {
      setState(
        () => _status = straighten ? 'Νέο: κόψιμο + OCR…' : 'Σήμερα: μόνο OCR…',
      );
      final r = await runBackgroundTest(
        jpegs: jpegs,
        straighten: straighten,
        intervalMs: _intervalMs,
        engine: widget.engine,
        ocr: widget.ocr,
        onProgress: (done, total) {
          if (mounted) {
            setState(
              () => _status =
                  '${straighten ? 'Νέο' : 'Σήμερα'}: $done από $total σελίδες έτοιμες',
            );
          }
        },
      );
      if (mounted) setState(() => _reports.add(r));
    }
    if (mounted) {
      setState(() {
        _running = false;
        _status = 'Τέλος';
      });
    }
  }

  String _seconds(int ms) => (ms / 1000).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Παρασκήνιο: ${widget.pages} σελίδες')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'Οι σελίδες είναι συνθετικά καρέ της εφαρμογής (όχι δικά σας έγγραφα). '
            'Έρχονται σαν λήψεις και επεξεργάζονται πίσω από την οθόνη. Η μπάρα '
            'παρακάτω κινείται συνέχεια: αν κολλήσει, η επεξεργασία βαραίνει το UI.',
          ),
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('όλες μαζί')),
              ButtonSegment(value: 1500, label: Text('1,5 s')),
              ButtonSegment(value: 2500, label: Text('2,5 s')),
              ButtonSegment(value: 4000, label: Text('4 s')),
            ],
            selected: {_intervalMs},
            onSelectionChanged: _running
                ? null
                : (s) => setState(() => _intervalMs = s.first),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _running ? null : _run,
            child: Text(_running ? 'Τρέχει…' : 'Εκτέλεση (σήμερα και νέο)'),
          ),
          const SizedBox(height: 8),
          Text(_status),
          const Divider(),
          for (final r in _reports) ...[
            Text(
              r.straighten ? 'ΝΕΟ (κόψιμο + OCR)' : 'ΣΗΜΕΡΑ (μόνο OCR)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              'Αναμονή μετά την τελευταία λήψη: ${_seconds(r.waitAfterLastMs)} s\n'
              'Συνολικός χρόνος: ${_seconds(r.totalMs)} s '
              '(τελευταία λήψη στα ${_seconds(r.lastShotMs)} s)\n'
              'Κόπηκαν: ${r.croppedPages} από ${r.pages} σελίδες\n'
              'Προετοιμασία ανά σελίδα (διάμεσος): ${_median(r.prepareMs)} ms, '
              'OCR: ${_median(r.ocrMs)} ms\n'
              'Καρέ της οθόνης πάνω από 16 ms: ${r.slowFrames} από ${r.frames}, '
              'πάνω από 33 ms: ${r.verySlowFrames}, χειρότερο: ${r.worstFrameMs} ms\n'
              'Μέγιστη μνήμη: ${r.peakRssMb} MB',
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  int _median(List<int> v) {
    if (v.isEmpty) return 0;
    final s = [...v]..sort();
    return s[s.length ~/ 2];
  }
}
