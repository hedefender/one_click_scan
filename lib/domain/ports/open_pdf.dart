/// What happened when the user asked to see the PDF.
enum OpenPdfResult {
  opened,

  /// No installed app can show a PDF.
  noViewer,

  /// The file could not be given to a viewer (it is gone, or access was lost).
  failed,
}

/// Shows a stored PDF in the viewer of the user's choice.
abstract interface class OpenPdf {
  /// [uri] is the document URI returned when the PDF was stored. Never throws.
  Future<OpenPdfResult> open(String uri);
}
