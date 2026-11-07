import '../entities/ocr_outcome.dart';

/// What became of the light correction (`flat`) of one page (ADR-030).
enum EnhancementOutcome {
  /// The corrected picture read more words: the PDF uses it.
  applied,

  /// The corrected picture read the same number of words or fewer: the PDF
  /// keeps the picture without correction (the safety valve).
  keptOriginal,

  /// The correction could not be made (error, timeout, cancel): nothing changed.
  failed,
}

enum EnhancementChoice { original, enhanced }

/// The safety valve of the correction: the version that reads **more words**
/// wins; a tie goes to the original. The picture of the PDF and its text layer
/// always come from the same version, so the PDF never loses content.
EnhancementChoice chooseByWords({
  required int originalWords,
  required int enhancedWords,
}) => enhancedWords > originalWords
    ? EnhancementChoice.enhanced
    : EnhancementChoice.original;

/// Words of a reading: the visible lines (the ones the PDF text layer uses)
/// split on white space. A page that was not read has none. Numbers only, the
/// text is never kept or logged.
int countWords(OcrOutcome? outcome) {
  if (outcome is! OcrSuccess) return 0;
  var words = 0;
  for (final line in outcome.result.visibleLines) {
    words += line.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }
  return words;
}
