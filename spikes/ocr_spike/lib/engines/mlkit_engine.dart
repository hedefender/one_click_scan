import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_engine.dart';

/// ML Kit Text Recognition v2, Latin script only (baseline).
class MlKitEngine implements SpikeOcrEngine {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  String get id => 'mlkit';

  @override
  String get languages => 'latin';

  @override
  Future<void> prepare() async {}

  @override
  Future<OcrResult> recognize(String imagePath) async {
    final watch = Stopwatch()..start();
    try {
      final result = await _recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      watch.stop();
      final lines = <OcrLine>[];
      final confidences = <double>[];
      for (final block in result.blocks) {
        for (final line in block.lines) {
          lines.add(
            OcrLine(line.text, line.boundingBox, confidence: line.confidence),
          );
          final c = line.confidence;
          if (c != null) confidences.add(c);
        }
      }
      return OcrResult(
        text: result.text,
        elapsedMs: watch.elapsedMilliseconds,
        lines: lines,
        confidence: confidences.isEmpty
            ? null
            : confidences.reduce((a, b) => a + b) / confidences.length,
      );
    } catch (e) {
      return OcrResult(
        text: '',
        elapsedMs: watch.elapsedMilliseconds,
        error: '${e.runtimeType}: $e'.replaceAll('\n', ' '),
      );
    }
  }

  @override
  Future<void> dispose() => _recognizer.close();
}
