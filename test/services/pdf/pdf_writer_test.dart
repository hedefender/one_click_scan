import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/pdf/pdf_text_layout.dart';
import 'package:one_click_scan/services/pdf/pdf_writer.dart';

import '../../support/pdf_inspect.dart';

void main() {
  late Directory dir;
  late Uint8List font;

  setUpAll(() {
    font = File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync();
  });

  setUp(() => dir = Directory.systemTemp.createTempSync('pdf_writer_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  PdfTextRun run(String text, {double x = 36, double y = 600}) => PdfTextRun(
    text: text,
    x: x,
    y: y,
    angle: 0,
    fontSize: 20,
    width: 40.0 * text.length,
  );

  Future<(PdfInspector, Uint8List, int)> write(
    List<PdfTextRun> runs, {
    int width = 1000,
    int height = 2000,
  }) async {
    final jpeg = writeTestJpeg('${dir.path}/page.jpg', width, height);
    final out = '${dir.path}/out.pdf';
    final size = await writePdf(
      PdfJob(
        pages: [
          PdfPageJob(
            imagePath: '${dir.path}/page.jpg',
            widthPx: width,
            heightPx: height,
            runs: runs,
          ),
        ],
        fontBytes: font,
        outputPath: out,
      ),
    );
    return (PdfInspector(File(out).readAsBytesSync()), jpeg, size);
  }

  test('a page with text: a page, the picture as it is, hidden text', () async {
    final (pdf, jpeg, size) = await write([run('Total'), run('12,50', y: 560)]);

    expect(pdf.pageCount, 1);
    expect(pdf.imageCount, 1);
    expect(pdf.usesJpegFilter, isTrue);
    expect(pdf.containsBytes(jpeg), isTrue, reason: 'JPEG not recompressed');
    expect(pdf.invisibleTextCount, 2);
    expect(pdf.visibleTextCount, 0);
    expect(pdf.hasToUnicode, isTrue);
    expect(size, pdf.bytes.length);
  });

  test('the page is the picture size at 200 dpi', () async {
    final (pdf, _, _) = await write([run('a')], width: 1000, height: 2000);

    final box = pdf.mediaBoxes.single;
    expect(box.$1, closeTo(360, 0.01));
    expect(box.$2, closeTo(720, 0.01));
  });

  test(
    'the text is searchable: ToUnicode lists Greek and Latin letters',
    () async {
      final (pdf, _, _) = await write([
        run('Σύνολο'),
        run('Total 12,50', y: 560),
        run('ΑΦΜ-123', y: 520),
      ]);

      final characters = pdf.toUnicodeCharacters;
      for (final ch in 'Σύνολο'.split('') + 'Total12,50ΑΦΜ-'.split('')) {
        expect(characters, contains(ch), reason: 'missing $ch');
      }
    },
  );

  test('a page with no text is the picture alone', () async {
    final (pdf, _, _) = await write(const []);

    expect(pdf.pageCount, 1);
    expect(pdf.imageCount, 1);
    expect(pdf.invisibleTextCount, 0);
  });

  test('only the used letters of the font are embedded (a subset)', () async {
    final (pdf, _, _) = await write([run('Total')]);

    expect(font.length, greaterThan(600000));
    // Picture of a flat colour + a few glyphs: far below the whole font.
    expect(pdf.bytes.length, lessThan(100000));
  });

  test(
    'many pages: one PDF page each, in order, each with its own size',
    () async {
      final a = writeTestJpeg('${dir.path}/a.jpg', 800, 1000);
      final b = writeTestJpeg('${dir.path}/b.jpg', 1000, 800, shade: 100);
      final c = writeTestJpeg('${dir.path}/c.jpg', 600, 600, shade: 50);
      final out = '${dir.path}/multi.pdf';

      await writePdf(
        PdfJob(
          pages: [
            PdfPageJob(
              imagePath: '${dir.path}/a.jpg',
              widthPx: 800,
              heightPx: 1000,
              runs: [run('one')],
            ),
            PdfPageJob(
              imagePath: '${dir.path}/b.jpg',
              widthPx: 1000,
              heightPx: 800,
              runs: const [],
            ),
            PdfPageJob(
              imagePath: '${dir.path}/c.jpg',
              widthPx: 600,
              heightPx: 600,
              runs: [run('three')],
            ),
          ],
          fontBytes: font,
          outputPath: out,
        ),
      );

      final pdf = PdfInspector(File(out).readAsBytesSync());
      expect(pdf.pageCount, 3);
      expect(pdf.imageCount, 3);
      expect(pdf.containsBytes(a), isTrue);
      expect(pdf.containsBytes(b), isTrue);
      expect(pdf.containsBytes(c), isTrue);
      expect(pdf.invisibleTextCount, 2); // page 2 has no text
      final boxes = pdf.mediaBoxes;
      expect(boxes[0].$1, closeTo(288, 0.01));
      expect(boxes[0].$2, closeTo(360, 0.01));
      expect(boxes[1].$1, closeTo(360, 0.01));
      expect(boxes[1].$2, closeTo(288, 0.01));
      expect(boxes[2].$1, closeTo(216, 0.01));
    },
  );

  test('a rotated word keeps its angle in the page', () async {
    final tilted = PdfTextRun(
      text: 'tilt',
      x: 100,
      y: 300,
      angle: -0.2,
      fontSize: 18,
      width: 80,
    );

    final (pdf, _, _) = await write([tilted]);

    expect(pdf.invisibleTextCount, 1);
    // The rotation shows up as a transformation matrix with sine terms.
    expect(pdf.content, matches(RegExp(r'-?0\.198\d* ')));
  });

  group('characters the font cannot draw', () {
    test(
      'control characters and unknown symbols are left out, no failure',
      () async {
        final (pdf, _, _) = await write([run('Σύν\u0001ολο​😀')]);

        expect(pdf.invisibleTextCount, 1);
        final characters = pdf.toUnicodeCharacters;
        expect(characters, contains('Σ'));
        expect(characters, isNot(contains('😀')));
        expect(characters, isNot(contains('​')));
        expect(characters, isNot(contains('\u0001')));
        // (The map also holds the library's own entry for glyph 0.)
      },
    );

    test('a word with nothing drawable adds no text at all', () async {
      final (pdf, _, _) = await write([run('😀😀'), run('\u0000')]);

      expect(pdf.invisibleTextCount, 0);
    });
  });

  group('no personal data and no metadata in the file', () {
    test('no EXIF, GPS, XMP or document information', () async {
      final (pdf, _, _) = await write([run('Total'), run('12,50', y: 560)]);
      final all = pdf.everything;

      for (final marker in [
        'Exif',
        'GPS',
        'xmp',
        'XMP',
        '/Author',
        '/Creator',
        '/Producer',
        '/Title',
        '/Subject',
        '/Keywords',
        '/CreationDate',
        '/ModDate',
        '/Info',
        '/Metadata',
      ]) {
        expect(all, isNot(contains(marker)), reason: 'found $marker');
      }
    });

    test('the only comments are the standard header ones; the trailer holds '
        'a random document ID and nothing about the user', () async {
      final (pdf, _, _) = await write([run('Total')]);
      final comments = pdf.everything
          .split('\n')
          .where((line) => line.startsWith('%'))
          .toList();

      // "%PDF-1.5", the binary marker, the library's address, "%%EOF".
      expect(comments.where((c) => !c.startsWith('%PDF')), hasLength(3));
      expect(comments, contains('%%EOF'));
      expect(pdf.everything, contains('/ID['));
      expect(
        RegExp(r'\d{4}-\d{2}-\d{2}').hasMatch(pdf.everything),
        isFalse,
        reason: 'no date in the file',
      );
    });

    test('the picture file has no metadata markers either', () async {
      final (pdf, jpeg, _) = await write([run('Total')]);

      // Marker 0xFFE1 (APP1: EXIF/XMP) is not in the JPEG header.
      var pos = 2;
      final markers = <int>[];
      while (pos + 4 <= jpeg.length && jpeg[pos] == 0xFF) {
        final m = jpeg[pos + 1];
        if (m == 0xDA) break;
        markers.add(m);
        pos += 2 + ((jpeg[pos + 2] << 8) | jpeg[pos + 3]);
      }
      expect(markers, isNot(contains(0xE1)));
      expect(pdf.containsBytes(jpeg), isTrue);
    });
  });
}
