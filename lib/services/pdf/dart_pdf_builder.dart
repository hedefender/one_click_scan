import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../../core/errors/app_exceptions.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/entities/pdf_page_input.dart';
import '../../domain/pdf/pdf_text_layout.dart';
import '../../domain/ports/pdf_builder.dart';
import 'pdf_writer.dart';

/// Writes the PDF with the `pdf` package in a background isolate (the UI
/// isolate only lays the words out, which takes a few milliseconds).
///
/// The pictures are the upright working copies of the OCR, read from the cache
/// by the isolate; the font is loaded once from the app's assets.
class DartPdfBuilder implements PdfBuilder {
  DartPdfBuilder({
    required this.workDirectory,
    required this.loadFont,
    required this.logger,
  });

  /// Folder of the app cache that holds the PDFs until they are stored.
  final Directory workDirectory;

  /// The bytes of the Noto Sans TrueType file.
  final Future<Uint8List> Function() loadFont;
  final AppLogger logger;

  Uint8List? _font;
  var _counter = 0;

  @override
  Future<BuiltPdf> build(List<PdfPageInput> pages) async {
    if (pages.isEmpty) {
      throw const ScanPdfException(ScanPdfFailure.buildFailed, 'no pages');
    }
    final watch = Stopwatch()..start();
    try {
      final font = _font ??= await loadFont();
      await workDirectory.create(recursive: true);
      _counter++;
      final output =
          '${workDirectory.path}${Platform.pathSeparator}'
          'scan_${DateTime.now().microsecondsSinceEpoch}_$_counter.pdf';
      final job = PdfJob(
        pages: [
          for (final page in pages)
            PdfPageJob(
              imagePath: page.image.path,
              widthPx: page.image.width,
              heightPx: page.image.height,
              runs: layoutPageText(
                lines: page.textLines,
                imageWidth: page.image.width,
                imageHeight: page.image.height,
              ),
            ),
        ],
        fontBytes: font,
        outputPath: output,
      );
      final size = await Isolate.run(() => writePdf(job));
      return BuiltPdf(
        path: output,
        pageCount: pages.length,
        textPageCount: job.pages.where((p) => p.runs.isNotEmpty).length,
        byteSize: size,
        duration: watch.elapsed,
      );
    } on ScanPdfException {
      rethrow;
    } catch (error, stackTrace) {
      // Only the type: a message could carry content of the document.
      logger.error(
        'PDF writer failed (${error.runtimeType})',
        null,
        stackTrace,
      );
      throw const ScanPdfException(ScanPdfFailure.buildFailed);
    }
  }

  @override
  Future<void> discard(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Best effort: purgeAll removes what stays.
    }
  }

  @override
  Future<void> purgeAll() async {
    try {
      if (await workDirectory.exists()) {
        await workDirectory.delete(recursive: true);
      }
    } on FileSystemException {
      // Best effort.
    }
  }
}
