import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/core/errors/app_exceptions.dart';
import 'package:one_click_scan/domain/entities/ocr_line.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';
import 'package:one_click_scan/domain/entities/ocr_result.dart';
import 'package:one_click_scan/domain/entities/pdf_page_input.dart';
import 'package:one_click_scan/domain/entities/upright_image.dart';
import 'package:one_click_scan/domain/ocr/char_boxes.dart';
import 'package:one_click_scan/services/pdf/dart_pdf_builder.dart';

import '../../support/fakes.dart';
import '../../support/pdf_inspect.dart';

OcrLine line(
  String text,
  double y, {
  double confidence = 0.95,
  bool filtered = false,
}) {
  final quad = [
    OcrPoint(0.1, y),
    OcrPoint(0.7, y),
    OcrPoint(0.7, y + 0.04),
    OcrPoint(0.1, y + 0.04),
  ];
  final n = text.length;
  return OcrLine(
    text: text,
    confidence: confidence,
    quad: quad,
    filtered: filtered,
    charBoxes: charBoxesFromSpans(quad, [
      for (var i = 0; i < n; i++) CharSpan(text[i], i / n, (i + 1) / n),
    ]),
  );
}

OcrSuccess success(List<OcrLine> lines, int w, int h) => OcrSuccess(
  OcrResult(
    lines: lines,
    packId: 'greek',
    duration: const Duration(seconds: 1),
    imageWidth: w,
    imageHeight: h,
  ),
);

void main() {
  late Directory dir;
  late DartPdfBuilder builder;
  late RecordingLogger logger;
  late Uint8List font;
  var fontLoads = 0;

  setUpAll(() {
    font = File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync();
  });

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pdf_builder_test');
    logger = RecordingLogger();
    fontLoads = 0;
    builder = DartPdfBuilder(
      workDirectory: Directory('${dir.path}/pdf_work'),
      loadFont: () async {
        fontLoads++;
        return font;
      },
      logger: logger,
    );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// A working copy on disk plus the OCR outcome for it.
  PdfPageInput page(
    String name,
    int w,
    int h,
    OcrOutcome Function(int, int) o,
  ) {
    final path = '${dir.path}/$name.jpg';
    writeTestJpeg(path, w, h);
    return PdfPageInput(
      image: UprightImage(
        path: path,
        width: w,
        height: h,
        sourceWidth: w * 2,
        sourceHeight: h * 2,
      ),
      outcome: o(w, h),
    );
  }

  test('one page: a PDF in the work folder with its numbers', () async {
    final input = page(
      'a',
      1000,
      1400,
      (w, h) => success([line('Σύνολο 12,50', 0.1)], w, h),
    );

    final built = await builder.build([input]);

    expect(built.path, startsWith('${dir.path}/pdf_work'));
    expect(built.pageCount, 1);
    expect(built.textPageCount, 1);
    expect(built.pagesWithoutText, 0);
    expect(File(built.path).lengthSync(), built.byteSize);
    final pdf = PdfInspector(File(built.path).readAsBytesSync());
    expect(pdf.pageCount, 1);
    expect(pdf.invisibleTextCount, 2); // two words
    expect(pdf.toUnicodeCharacters, containsAll(['Σ', 'ύ', '1', ',']));
  });

  test('three pages in order; the ones that failed have no text', () async {
    final pages = [
      page('p1', 800, 1000, (w, h) => success([line('Total', 0.1)], w, h)),
      page('p2', 800, 1000, (w, h) => const OcrTimedOut(Duration(seconds: 45))),
      page('p3', 800, 1000, (w, h) => const OcrCancelled()),
      page(
        'p4',
        800,
        1000,
        (w, h) => const OcrFailed(OcrFailureReason.engineError),
      ),
    ];

    final built = await builder.build(pages);

    expect(built.pageCount, 4);
    expect(built.textPageCount, 1);
    expect(built.pagesWithoutText, 3);
    final pdf = PdfInspector(File(built.path).readAsBytesSync());
    expect(pdf.pageCount, 4);
    expect(pdf.imageCount, 4);
  });

  test('filtered lines (low confidence) are not written', () async {
    final input = page(
      'a',
      1000,
      1400,
      (w, h) => success(
        [
          line('Keep', 0.1),
          line('Δύσκολο', 0.3, confidence: 0.4, filtered: true),
        ],
        w,
        h,
      ),
    );

    final built = await builder.build([input]);

    final pdf = PdfInspector(File(built.path).readAsBytesSync());
    expect(pdf.invisibleTextCount, 1);
    expect(pdf.toUnicodeCharacters, contains('K'));
    expect(pdf.toUnicodeCharacters, isNot(contains('Δ')));
  });

  test('a page whose lines are all filtered counts as without text', () async {
    final input = page(
      'a',
      1000,
      1400,
      (w, h) => success([line('noise', 0.1, filtered: true)], w, h),
    );

    final built = await builder.build([input]);

    expect(built.textPageCount, 0);
  });

  test('the font is loaded once for several PDFs', () async {
    final input = page(
      'a',
      600,
      800,
      (w, h) => success([line('x', 0.1)], w, h),
    );

    await builder.build([input]);
    await builder.build([input]);

    expect(fontLoads, 1);
  });

  test('two PDFs never share a file name', () async {
    final input = page(
      'a',
      600,
      800,
      (w, h) => success([line('x', 0.1)], w, h),
    );

    final first = await builder.build([input]);
    final second = await builder.build([input]);

    expect(second.path, isNot(first.path));
  });

  test('a missing picture is a controlled failure, not a crash', () async {
    final input = PdfPageInput(
      image: const UprightImage(
        path: 'does/not/exist.jpg',
        width: 100,
        height: 100,
        sourceWidth: 100,
        sourceHeight: 100,
      ),
      outcome: const OcrCancelled(),
    );

    await expectLater(
      builder.build([input]),
      throwsA(
        isA<ScanPdfException>().having(
          (e) => e.failure,
          'failure',
          ScanPdfFailure.buildFailed,
        ),
      ),
    );
    expect(logger.messages.single, startsWith('PDF writer failed'));
  });

  test('no pages is a failure', () async {
    await expectLater(
      builder.build(const []),
      throwsA(isA<ScanPdfException>()),
    );
  });

  test('the log line of a failure carries no document text', () async {
    final input = PdfPageInput(
      image: const UprightImage(
        path: 'does/not/exist.jpg',
        width: 100,
        height: 100,
        sourceWidth: 100,
        sourceHeight: 100,
      ),
      outcome: success([line('SECRET-TEXT', 0.1)], 100, 100),
    );

    await expectLater(builder.build([input]), throwsA(anything));

    expect(logger.messages.join(), isNot(contains('SECRET')));
  });

  test('discard removes the file, purgeAll the folder', () async {
    final input = page(
      'a',
      600,
      800,
      (w, h) => success([line('x', 0.1)], w, h),
    );
    final built = await builder.build([input]);
    expect(File(built.path).existsSync(), isTrue);

    await builder.discard(built.path);
    expect(File(built.path).existsSync(), isFalse);
    await builder.discard(built.path); // already gone: no error

    final again = await builder.build([input]);
    await builder.purgeAll();
    expect(File(again.path).existsSync(), isFalse);
    expect(Directory('${dir.path}/pdf_work').existsSync(), isFalse);
    await builder.purgeAll(); // nothing left: no error
  });
}
