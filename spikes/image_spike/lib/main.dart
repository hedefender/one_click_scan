import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'phone/background_page.dart';
import 'phone/ocr_service.dart';
import 'phone/pipeline.dart';
import 'phone/review_page.dart';
import 'phone/verdicts.dart';

/// The phone screens of the image spike (Phase 6.0). Nothing is sent anywhere
/// and no picture is stored: photos are read, shown, and dropped. The only
/// file written is the list of your answers (numbers and yes/no).
void main() => runApp(const SpikeApp());

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Image spike',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _store = VerdictStore();
  final _picker = ImagePicker();
  var _engine = Engine.openCv;
  SpikeOcr? _ocr;
  var _ocrError = '';

  Future<SpikeOcr?> _ensureOcr() async {
    if (_ocr != null) return _ocr;
    try {
      return _ocr = await SpikeOcr.create();
    } catch (e) {
      setState(() => _ocrError = 'Το OCR δεν ξεκίνησε: ${e.runtimeType}');
      return null;
    }
  }

  Future<void> _review(List<String> paths) async {
    if (paths.isEmpty || !mounted) return;
    final ocr = await _ensureOcr();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ReviewPage(paths: paths, engine: _engine, store: _store, ocr: ocr),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _camera() async {
    final shot = await _picker.pickImage(source: ImageSource.camera);
    if (shot != null) await _review([shot.path]);
  }

  Future<void> _gallery() async {
    final shots = await _picker.pickMultiImage();
    await _review([for (final s in shots) s.path]);
  }

  Future<void> _background(int pages) async {
    final ocr = await _ensureOcr();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BackgroundPage(pages: pages, engine: _engine, ocr: ocr),
      ),
    );
  }

  Future<void> _saveAnswers() async {
    final file = await _store.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Αποθηκεύτηκε: ${file.path}')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Image spike · Phase 6.0')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Δοκιμή κοψίματος και ισιώματος σελίδας. Τίποτα δεν στέλνεται και καμία '
            'φωτογραφία δεν αποθηκεύεται από αυτή την εφαρμογή.',
          ),
          const SizedBox(height: 12),
          SegmentedButton<Engine>(
            segments: [
              for (final e in Engine.values)
                ButtonSegment(value: e, label: Text(e.label)),
            ],
            selected: {_engine},
            onSelectionChanged: (s) => setState(() => _engine = s.first),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _camera,
            child: const Text('Φωτογραφία με την κάμερα'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _gallery,
            child: const Text('Επιλογή φωτογραφιών από τη συλλογή'),
          ),
          const Divider(height: 32),
          OutlinedButton(
            onPressed: () => _background(5),
            child: const Text('Δοκιμή παρασκηνίου: 5 σελίδες'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _background(21),
            child: const Text('Δοκιμή παρασκηνίου: 21 σελίδες'),
          ),
          const Divider(height: 32),
          Text(
            'Απαντήσεις: ${_store.verdicts.length} '
            '(ΝΑΙ ${_store.verdicts.where((v) => v.good).length}, '
            'ΟΧΙ ${_store.verdicts.where((v) => !v.good).length})',
          ),
          const SizedBox(height: 8),
          if (_store.verdicts.isNotEmpty) Text(_store.summary()),
          OutlinedButton(
            onPressed: _store.verdicts.isEmpty ? null : _saveAnswers,
            child: const Text('Αποθήκευση απαντήσεων (αριθμοί και ΝΑΙ/ΟΧΙ)'),
          ),
          if (_ocrError.isNotEmpty) Text(_ocrError),
        ],
      ),
    );
  }
}
