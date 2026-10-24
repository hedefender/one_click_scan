import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'bench.dart';
import 'ocr/spike_ocr.dart';
import 'pdf/layout.dart';
import 'sheet/sheet.dart';

/// `--dart-define=AUTORUN=bench` runs the whole benchmark on start-up (used on
/// the emulator) and writes the files for tool/analyze.py; `AUTORUN=cmd` obeys `out/command.txt` (emulator driver).
const _autorun = String.fromEnvironment('AUTORUN');

void main() {
  runApp(const SpikeApp());
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PDF spike',
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    home: const Home(),
  );
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final _log = <String>[];
  final _files = <File>[];
  String _pack = 'greek';
  SpikeOcr? _ocr;
  String? _ocrPack;
  ByteData? _font;
  Directory? _out;
  bool _busy = false;
  Map<String, String> _expected = {};

  @override
  void initState() {
    super.initState();
    if (_autorun == 'bench') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bench());
    } else if (_autorun == 'cmd') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _command());
    }
  }

  /// Emulator driver: reads `out/command.txt` (`open <file>` or `clip`) and
  /// does it, printing one line. Lets a script open a PDF in a viewer, copy
  /// text there, and compare the clipboard with the invented expected code.
  Future<void> _command() async {
    await _prepare();
    final cmd = File('${_out!.path}/command.txt');
    final text = cmd.existsSync() ? cmd.readAsStringSync().trim() : '';
    if (text == 'bench') {
      await _bench();
    } else if (text.startsWith('open ')) {
      final name = text.substring(5);
      final r = await OpenFilex.open(
        '${_out!.path}/$name',
        type: 'application/pdf',
      );
      _say('PDFSPIKE open $name -> ${r.type.name}');
    } else if (text == 'clear') {
      await Clipboard.setData(const ClipboardData(text: '-'));
      _say('PDFSPIKE clipboard cleared');
    } else if (text.startsWith('clip ')) {
      final want = text.substring(5);
      await Future<void>.delayed(const Duration(seconds: 1));
      final got = (await Clipboard.getData('text/plain'))?.text ?? '';
      final clean = got.replaceAll(RegExp(r'\s'), '');
      _say(
        'PDFSPIKE clip want ${want.length} got ${got.length} '
        'exact=${clean == want} text=[$got]',
      );
    }
  }

  void _say(String line) {
    debugPrint(line);
    if (mounted) setState(() => _log.insert(0, line));
  }

  Future<void> _prepare() async {
    _out ??= Directory(
      '${(await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory()).path}/out',
    )..createSync(recursive: true);
    _font ??= await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    if (_ocr == null || _ocrPack != _pack) {
      await _ocr?.dispose();
      _ocr = await SpikeOcr.create(_pack);
      _ocrPack = _pack;
    }
  }

  Future<void> _guard(Future<void> Function() body) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await body();
    } catch (e, st) {
      _say('PDFSPIKE ERROR ${e.runtimeType}');
      debugPrint('$st');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sheet() => _guard(() async {
    await _prepare();
    final spec = paymentSheet(1);
    final r = await processSheet(
      out: _out!,
      spec: spec,
      ocr: _ocr!,
      font: _font!,
      report: _say,
    );
    _say('PDFSPIKE sheet ${jsonEncode(r)}');
    final texts = spec.lines.map((l) => l.text).join('\n');
    _expected = {
      'RF code': RegExp(r'RF\d{21}').firstMatch(texts)!.group(0)!,
      'IBAN': RegExp(r'GR\d{25}').firstMatch(texts)!.group(0)!,
      'Invoice no': RegExp(r'2026-\d{5}').firstMatch(texts)!.group(0)!,
      'Amount': RegExp(r'ΣΥΝΟΛΟ (\S+)').firstMatch(texts)!.group(1)!,
    };
    _refreshFiles();
  });

  void _refreshFiles() {
    final list =
        _out!
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.pdf'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    setState(() {
      _files
        ..clear()
        ..addAll(list);
    });
  }

  Future<void> _photo() => _guard(() async {
    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty) return;
    final path = picked.first.path;
    if (path == null) return;
    await _prepare();
    final sw = Stopwatch()..start();
    final jpeg = await workingJpegFromFile(path);
    final prepMs = sw.elapsedMilliseconds;
    final page = await _ocr!.recognize(jpeg);
    final pages = [PageSpec(jpeg: jpeg, page: page)];
    _say(
      'PDFSPIKE photo working ${page.width}x${page.height} ${jpeg.length} B '
      'prep $prepMs ms, ocr ${page.millis} ms, boxes ${page.lines.length}',
    );
    for (final writer in Writer.values) {
      for (final mode in [TextMode.line, TextMode.word]) {
        final r = await buildPdfFile(
          out: _out!,
          stem: 'photo',
          writer: writer,
          mode: mode,
          pages: pages,
          font: _font!,
        );
        _say(
          'PDFSPIKE photo ${r.file.uri.pathSegments.last} ${r.bytes} B ${r.millis} ms',
        );
      }
    }
    _refreshFiles();
  });

  Future<void> _bench() => _guard(() async {
    await _prepare();
    final results = <Object?>[];
    final specs = [
      paymentSheet(1),
      paymentSheet(2),
      paymentSheet(3),
      paymentSheet(4),
      paymentSheet(5, tilt: 2.5, noise: 4),
      paymentSheet(6, tilt: -1.5, noise: 6),
      paymentSheet(7, noise: 6),
      receiptSheet(),
      densePage(),
    ];
    for (final spec in specs) {
      results.add(
        await processSheet(
          out: _out!,
          spec: spec,
          ocr: _ocr!,
          font: _font!,
          report: _say,
        ),
      );
    }
    // Three pages in one PDF.
    final pages = <PageSpec>[];
    for (final seed in [1, 2, 3]) {
      final jpeg = File('${_out!.path}/sheet$seed.jpg').readAsBytesSync();
      pages.add(PageSpec(jpeg: jpeg, page: await _ocr!.recognize(jpeg)));
    }
    for (final writer in Writer.values) {
      final r = await buildPdfFile(
        out: _out!,
        stem: 'multi3',
        writer: writer,
        mode: TextMode.word,
        pages: pages,
        font: _font!,
      );
      _say(
        'PDFSPIKE pdf ${r.file.uri.pathSegments.last} ${r.bytes} B ${r.millis} ms',
      );
    }
    File('${_out!.path}/bench_summary.json').writeAsStringSync(
      jsonEncode({'fontFileBytes': _font!.lengthInBytes, 'sheets': results}),
    );
    _say('PDFSPIKE done');
    _refreshFiles();
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PDF spike (searchable text)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Greek + English'),
                selected: _pack == 'greek',
                onSelected: (_) => setState(() => _pack = 'greek'),
              ),
              ChoiceChip(
                label: const Text('Latin'),
                selected: _pack == 'latin',
                onSelected: (_) => setState(() => _pack = 'latin'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _sheet,
            child: const Text('1. Make the test sheet and its PDFs'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _photo,
            child: const Text('2. Pick a photo of a real document'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _expected.isEmpty
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ComparePage(expected: _expected),
                    ),
                  ),
            child: const Text('3. Paste what you copied and compare'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Working...'),
            ),
          const Divider(),
          for (final f in _files)
            ListTile(
              dense: true,
              title: Text(f.uri.pathSegments.last),
              subtitle: Text(
                '${(f.lengthSync() / 1024).toStringAsFixed(0)} KB',
              ),
              trailing: Wrap(
                children: [
                  TextButton(
                    onPressed: () =>
                        OpenFilex.open(f.path, type: 'application/pdf'),
                    child: const Text('Open'),
                  ),
                  TextButton(
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(files: [XFile(f.path)]),
                    ),
                    child: const Text('Share'),
                  ),
                ],
              ),
            ),
          const Divider(),
          for (final l in _log.take(40))
            Text(l, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

/// The user pastes what a viewer copied; only numbers come out.
class ComparePage extends StatefulWidget {
  const ComparePage({super.key, required this.expected});

  final Map<String, String> expected;

  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  late String _key = widget.expected.keys.first;
  final _controller = TextEditingController();
  String _result = '';

  void _compare() {
    final want = widget.expected[_key]!;
    final raw = _controller.text;
    final got = raw.replaceAll(RegExp(r'\s'), '');
    var prefix = 0;
    while (prefix < want.length &&
        prefix < got.length &&
        want[prefix] == got[prefix]) {
      prefix++;
    }
    var same = 0;
    for (var i = 0; i < want.length && i < got.length; i++) {
      if (want[i] == got[i]) same++;
    }
    final contains = got.contains(want);
    final exact = got == want;
    setState(() {
      _result =
          'expected ${want.length} chars, pasted ${got.length} chars '
          '(${raw.length - got.length} blanks removed)\n'
          'exact: ${exact ? 'YES' : 'no'}; contains the whole expected: '
          '${contains ? 'yes' : 'no'}\n'
          'first difference at position ${prefix == want.length && prefix == got.length ? 'none' : prefix + 1}\n'
          'characters equal at the same position: $same of ${want.length}';
    });
    debugPrint(
      'PDFSPIKE compare $_key exact=$exact prefix=$prefix same=$same '
      'want=${want.length} got=${got.length}',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Compare')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          DropdownButton<String>(
            value: _key,
            items: [
              for (final k in widget.expected.keys)
                DropdownMenuItem(value: k, child: Text(k)),
            ],
            onChanged: (v) => setState(() => _key = v!),
          ),
          Text('Expected (invented): ${widget.expected[_key]}'),
          TextField(controller: _controller, minLines: 2, maxLines: 6),
          FilledButton(onPressed: _compare, child: const Text('Compare')),
          Text(_result),
        ],
      ),
    ),
  );
}
