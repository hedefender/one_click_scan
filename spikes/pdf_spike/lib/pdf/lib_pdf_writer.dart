import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:vector_math/vector_math_64.dart';

import 'layout.dart';

/// The same PDF written with the `pdf` package (dart_pdf): the picture as a
/// JPEG and the hidden text with text render mode 3 (invisible) in a TrueType
/// font that dart_pdf subsets (only the glyphs used are embedded) and gives a
/// `ToUnicode` map.
Future<Uint8List> buildLibPdf(
  List<PageSpec> pages,
  TextMode mode,
  ByteData fontBytes,
) async {
  final doc = PdfDocument(compress: true);
  final font = PdfTtfFont(doc, fontBytes);
  for (final spec in pages) {
    final page = PdfPage(
      doc,
      pageFormat: PdfPageFormat(spec.pageWidth, spec.pageHeight),
    );
    final g = page.getGraphics();
    final image = PdfImage.jpeg(doc, image: spec.jpeg);
    g.drawImage(image, 0, 0, spec.pageWidth, spec.pageHeight);
    for (final r in layoutRuns(spec, mode)) {
      final natural = font.stringMetrics(r.text).advanceWidth * r.fontSize;
      final scale = natural <= 0 ? 1.0 : r.width / natural;
      g.saveContext();
      g.setTransform(
        Matrix4.identity()
          ..translateByDouble(r.x, r.y, 0, 1)
          ..rotateZ(r.angle),
      );
      g.drawString(
        font,
        r.fontSize,
        r.text,
        0,
        0,
        scale: scale,
        mode: PdfTextRenderingMode.invisible,
      );
      g.restoreContext();
    }
  }
  return Uint8List.fromList(await doc.save());
}

/// Size in bytes of the embedded font if the whole file were embedded (what
/// dart_pdf would write without subsetting is not offered; this is the file).
int fullFontBytes(ByteData fontBytes) => math.max(0, fontBytes.lengthInBytes);
