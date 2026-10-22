import 'dart:ui';

/// One recognised line (or word) with its box in the pixel space of the
/// image that was given to the engine.
class OcrLine {
  const OcrLine(this.text, this.box, {this.confidence});
  final String text;
  final Rect box;
  final double? confidence;
}

class OcrResult {
  const OcrResult({
    required this.text,
    required this.elapsedMs,
    this.lines = const [],
    this.confidence,
    this.error,
    this.breakdown = const {},
  });

  final String text;
  final int elapsedMs;

  /// Empty when the engine gives no geometry.
  final List<OcrLine> lines;

  /// Mean confidence 0..1 when the engine reports one.
  final double? confidence;
  final String? error;

  /// Optional timing/size breakdown (ms, counts) for the engines that have steps.
  final Map<String, int> breakdown;

  bool get hasGeometry => lines.isNotEmpty;
}

/// First sketch of the future `OcrEngine`. Input is a file path because that
/// is what ML Kit and Tesseract take; PaddleOCR decodes the file itself.
abstract class SpikeOcrEngine {
  String get id;

  /// Languages the engine is configured for (informational).
  String get languages;

  Future<void> prepare() async {}

  Future<OcrResult> recognize(String imagePath);

  Future<void> dispose() async {}
}
