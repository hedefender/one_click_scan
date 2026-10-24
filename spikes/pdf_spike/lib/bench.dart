import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'ocr/spike_ocr.dart';
import 'pdf/layout.dart';
import 'pdf/lib_pdf_writer.dart';
import 'pdf/raw_pdf_writer.dart';
import 'sheet/sheet.dart';

/// Prints one machine readable line (numbers only) to logcat and the screen.
typedef Report = void Function(String line);

/// type3: hand-written PDF with a Type 3 glyphless font. glyphless:
/// hand-written PDF with a generated empty TrueType. lib: the `pdf` package
/// with a Noto Sans subset.
enum Writer { type3, glyphless, lib }

/// The upright working copy: JPEG, long side at most 2560, no EXIF, no GPS
/// (the encoder writes none and the source's metadata is not copied).
Uint8List workingJpeg(img.Image image, {int quality = 90}) {
  var out = image;
  final longSide = out.width > out.height ? out.width : out.height;
  if (longSide > 2560) {
    final s = 2560 / longSide;
    out = img.copyResize(
      out,
      width: (out.width * s).round(),
      height: (out.height * s).round(),
      interpolation: img.Interpolation.average,
    );
  }
  final clean = img.Image.from(out)..exif.clear();
  return img.encodeJpg(clean, quality: quality);
}

/// Decode a picked photo (orientation applied by the decoder) and make the
/// working copy, off the UI isolate.
Future<Uint8List> workingJpegFromFile(String path) => Isolate.run(() {
  final image = img.decodeImage(File(path).readAsBytesSync())!;
  return workingJpeg(image);
});

Future<Uint8List> _build(
  Writer writer,
  TextMode mode,
  List<PageSpec> pages,
  ByteData font,
) => Isolate.run(() async {
  switch (writer) {
    case Writer.type3:
      return buildRawPdf(pages, mode);
    case Writer.glyphless:
      return buildRawPdf(pages, mode, font: GlyphlessFont.glyphlessTtf);
    case Writer.lib:
      return buildLibPdf(pages, mode, font);
  }
});

class BuildResult {
  BuildResult(this.file, this.bytes, this.millis);

  final File file;
  final int bytes;
  final int millis;
}

Future<BuildResult> buildPdfFile({
  required Directory out,
  required String stem,
  required Writer writer,
  required TextMode mode,
  required List<PageSpec> pages,
  required ByteData font,
}) async {
  final sw = Stopwatch()..start();
  final bytes = await _build(writer, mode, pages, font);
  final ms = sw.elapsedMilliseconds;
  final file = File('${out.path}/${stem}_${writer.name}_${mode.letter}.pdf')
    ..writeAsBytesSync(bytes);
  return BuildResult(file, bytes.length, ms);
}

Map<String, Object?> pageToJson(SpikePage page) => {
  'width': page.width,
  'height': page.height,
  'ms': page.millis,
  'lines': [
    for (final l in page.lines)
      {
        'text': l.text,
        'conf': l.confidence,
        'cx': l.box.cx,
        'cy': l.box.cy,
        'w': l.box.w,
        'h': l.box.h,
        'angle': l.box.angle,
        'chars': [
          for (final c in l.chars) [c.ch, c.x0, c.x1],
        ],
      },
  ],
};

/// Renders [spec], reads it, writes every PDF variant. Returns the numbers.
Future<Map<String, Object?>> processSheet({
  required Directory out,
  required SheetSpec spec,
  required SpikeOcr ocr,
  required ByteData font,
  required Report report,
  bool writeAllVariants = true,
}) async {
  final rendered = await renderSheet(spec);
  final jpeg = workingJpeg(rendered.image);
  File('${out.path}/${spec.name}.jpg').writeAsBytesSync(jpeg);
  File('${out.path}/${spec.name}_truth.json')
      .writeAsStringSync(jsonEncode(rendered.toJson(spec.name)));
  final page = await ocr.recognize(jpeg);
  File('${out.path}/${spec.name}_ocr.json')
      .writeAsStringSync(jsonEncode(pageToJson(page)));
  final result = <String, Object?>{
    'name': spec.name,
    'image': '${page.width}x${page.height}',
    'jpegBytes': jpeg.length,
    'ocrMs': page.millis,
    'lines': page.lines.length,
    'pdfs': <Object?>[],
  };
  final spec1 = PageSpec(jpeg: jpeg, page: page);
  for (final writer in Writer.values) {
    for (final mode in TextMode.values) {
      if (!writeAllVariants && mode == TextMode.code) continue;
      final r = await buildPdfFile(
        out: out,
        stem: spec.name,
        writer: writer,
        mode: mode,
        pages: [spec1],
        font: font,
      );
      (result['pdfs']! as List).add({
        'file': r.file.uri.pathSegments.last,
        'bytes': r.bytes,
        'ms': r.millis,
      });
      report(
        'PDFSPIKE pdf ${r.file.uri.pathSegments.last} ${r.bytes} B ${r.millis} ms',
      );
    }
  }
  return result;
}
