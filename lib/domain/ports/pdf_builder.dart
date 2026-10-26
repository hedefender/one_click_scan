import '../entities/pdf_page_input.dart';

/// Writes the PDF of a scan into the app cache. The implementation
/// (`services/pdf/`) runs in a background isolate; nothing outside it knows
/// which library writes the file.
abstract interface class PdfBuilder {
  /// One page per element of [pages], in order: the picture, and when the OCR
  /// succeeded an invisible text layer, one piece of text per word. Throws
  /// `ScanPdfException`.
  Future<BuiltPdf> build(List<PdfPageInput> pages);

  /// Deletes a file made by [build] (best effort, never throws).
  Future<void> discard(String path);

  /// Removes every file left in the cache (a killed run), at start-up.
  Future<void> purgeAll();
}
