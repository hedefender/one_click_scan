import '../entities/ocr_result.dart';
import 'ocr_config.dart';

/// Flags the lines whose confidence is below [threshold]. The text is never
/// changed and no line is removed: the raw result stays complete.
OcrResult applyConfidenceFilter(
  OcrResult result, {
  double threshold = OcrConfig.minLineConfidence,
}) {
  return result.copyWith(
    lines: [
      for (final line in result.lines)
        line.copyWith(filtered: line.confidence < threshold),
    ],
  );
}
