import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'phone/background_runner.dart';
import 'phone/ocr_service.dart';
import 'phone/pipeline.dart';

/// Headless run of the background test on the emulator (ENTRY=lib/bg_eval_main.dart
/// MARK=BGEVAL): the same code as the phone screen, many scenarios, numbers only.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  try {
    final manifest = (jsonDecode(
      await rootBundle.loadString('assets/eval_full/manifest.json'),
    ) as List).cast<Map<String, Object?>>();
    // The pages with a document and a Greek text (the Greek pack reads both).
    final ids = [
      for (final e in manifest)
        if (e['truth'] != null &&
            e['partial'] == false &&
            e['fillsFrame'] == false)
          e['id']! as String,
    ];
    Future<List<Uint8List>> load(int n) async => [
      for (var i = 0; i < n; i++)
        (await rootBundle.load('assets/eval_full/${ids[i % ids.length]}.jpg'))
            .buffer
            .asUint8List(),
    ];
    final ocr = await SpikeOcr.create();
    // Warm up the models so loading is in no timing.
    final warm = await load(1);
    await runBackgroundTest(
      jpegs: warm,
      straighten: false,
      intervalMs: 0,
      engine: Engine.dart,
      ocr: ocr,
    );
    _line('BGEVAL info warm-up done');
    final scenarios = <(int, int, bool, Engine)>[
      (5, 0, false, Engine.dart),
      (5, 0, true, Engine.dart),
      (5, 2500, false, Engine.dart),
      (5, 2500, true, Engine.dart),
      (21, 0, false, Engine.dart),
      (21, 0, true, Engine.dart),
      (21, 0, true, Engine.openCv),
      (21, 2500, false, Engine.dart),
      (21, 2500, true, Engine.dart),
    ];
    for (final (n, interval, straighten, engine) in scenarios) {
      final r = await runBackgroundTest(
        jpegs: await load(n),
        straighten: straighten,
        intervalMs: interval,
        engine: engine,
        ocr: ocr,
      );
      _line('BGEVAL run ${r.summary()}');
    }
    await ocr.dispose();
    _line('BGEVAL done');
  } catch (error, stack) {
    _line('BGEVAL FAILED ${error.runtimeType}: $error');
    _line('BGEVAL stack ${stack.toString().split('\n').take(6).join(' | ')}');
  }
}

void _line(String s) {
  // ignore: avoid_print
  print(s);
}
