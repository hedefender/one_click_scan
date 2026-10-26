import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../domain/pdf/pdf_text_layout.dart';

/// One page for the writer: a JPEG file and the hidden words on it. Plain
/// values only, so the job can be sent to a background isolate.
class PdfPageJob {
  const PdfPageJob({
    required this.imagePath,
    required this.widthPx,
    required this.heightPx,
    required this.runs,
  });

  final String imagePath;
  final int widthPx;
  final int heightPx;
  final List<PdfTextRun> runs;
}

class PdfJob {
  const PdfJob({
    required this.pages,
    required this.fontBytes,
    required this.outputPath,
  });

  final List<PdfPageJob> pages;

  /// The TrueType file of the hidden-text font (Noto Sans).
  final Uint8List fontBytes;
  final String outputPath;
}

/// Writes the PDF of [job] to `job.outputPath` and returns its size in bytes.
///
/// Each page is the picture, drawn as it is (a JPEG goes in without new
/// compression), and over it one invisible piece of text per word (text
/// render mode 3) in Noto Sans. The `pdf` package embeds only the glyphs that
/// are used and writes a `ToUnicode` map, so a viewer can search and select
/// the text. No document information (author, producer, dates) is written and
/// the picture carries no EXIF.
///
/// Runs in a background isolate (`DartPdfBuilder`); it is a plain function so
/// that tests can call it directly.
Future<int> writePdf(PdfJob job) async {
  final doc = PdfDocument(compress: true);
  final fontData = ByteData.sublistView(job.fontBytes);
  final font = PdfTtfFont(doc, fontData);

  for (final spec in job.pages) {
    final size = pageSizeFor(spec.widthPx, spec.heightPx);
    final page = PdfPage(
      doc,
      pageFormat: PdfPageFormat(size.width, size.height),
    );
    final canvas = page.getGraphics();
    final image = PdfImage.jpeg(
      doc,
      image: await File(spec.imagePath).readAsBytes(),
    );
    canvas.drawImage(image, 0, 0, size.width, size.height);

    for (final run in spec.runs) {
      final text = _drawable(font, run.text);
      if (text.isEmpty) continue;
      final natural = font.stringMetrics(text).advanceWidth * run.fontSize;
      final stretch = natural <= 0 ? 1.0 : run.width / natural;
      canvas
        ..saveContext()
        ..setTransform(
          Matrix4.identity()
            ..translateByDouble(run.x, run.y, 0, 1)
            ..rotateZ(run.angle),
        )
        ..drawString(
          font,
          run.fontSize,
          text,
          0,
          0,
          scale: stretch,
          mode: PdfTextRenderingMode.invisible,
        )
        ..restoreContext();
    }
  }

  final bytes = await doc.save();
  await File(job.outputPath).writeAsBytes(bytes, flush: true);
  return bytes.length;
}

/// [text] without the characters the font has no glyph for (control
/// characters and the like). The picture is the document; the hidden text is a
/// convenience, so a character the font cannot draw is left out of it.
String _drawable(PdfFont font, String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    if (_isInvisible(rune) || !font.isRuneSupported(rune)) continue;
    buffer.writeCharCode(rune);
  }
  return buffer.toString();
}

/// Control and format characters (zero-width space, joiners, direction marks,
/// the byte order mark, soft hyphen): they print nothing and only disturb a
/// search.
bool _isInvisible(int rune) =>
    rune < 0x20 ||
    (rune >= 0x7F && rune <= 0x9F) ||
    rune == 0xAD ||
    (rune >= 0x200B && rune <= 0x200F) ||
    (rune >= 0x2028 && rune <= 0x202E) ||
    (rune >= 0x2060 && rune <= 0x206F) ||
    rune == 0xFEFF;
