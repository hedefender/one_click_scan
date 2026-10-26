import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/core/errors/app_exceptions.dart';
import 'package:one_click_scan/core/logging/app_logger.dart';
import 'package:one_click_scan/domain/entities/captured_page.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';
import 'package:one_click_scan/domain/entities/ocr_progress.dart';
import 'package:one_click_scan/domain/entities/pdf_page_input.dart';
import 'package:one_click_scan/domain/entities/upright_image.dart';
import 'package:one_click_scan/domain/ocr/ocr_cancellation.dart';
import 'package:one_click_scan/domain/ocr/ocr_language_pack_registry.dart';
import 'package:one_click_scan/domain/ports/ocr_engine.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/domain/usecases/prepare_image_for_ocr.dart';
import 'package:one_click_scan/domain/usecases/recognize_pages.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/ocr/ocr_keys.dart';
import 'package:one_click_scan/features/scan/scan_keys.dart';
import 'package:one_click_scan/services/ocr/ocr_services.dart';
import 'package:one_click_scan/services/pdf/pdf_services.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/fakes.dart';
import '../test/support/pdf_fakes.dart';
import '../test/support/pdf_inspect.dart';
import '../test/support/scan_fakes.dart';
import 'support/directory_scan_file_store.dart';
import 'support/synthetic_pages.dart';

/// Phase 3 on the Claude Code emulator: the real OCR models, the real PDF
/// writer (background isolate), the whole screen flow, invented pages only.
///   tool/run_pdf_integration_test.sh `<emulator-id>`
///
/// The folder of the user is a real directory (the system folder picker needs a
/// person), so the PDFs that come out are really written and are copied to
/// `pdf_it/` of the app's private files folder, where the runner script reads
/// them with `run-as` and copies them to the PC for the text extraction with PyMuPDF and `pdftotext`.
/// Sizes and times are printed as `PDFIT ...` lines; none is asserted (an x86
/// emulator says nothing about the speed of a phone).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late OcrServices ocr;
  late PdfServices pdf;
  late Directory cache;
  late Directory out; // pulled by the runner script
  late Directory work; // inputs of the tests
  late img.Image greekPage;
  late img.Image latinPage;

  void report(String message) {
    // ignore: avoid_print
    print('PDFIT $message');
  }

  /// Keeps a copy of a PDF for the PC and gives the runner time to pull it.
  Future<void> keep(String path, String name) async {
    File(path).copySync('${out.path}/$name');
    await Future<void>.delayed(const Duration(seconds: 7));
  }

  Directory workDir(String name) => Directory('${cache.path}/$name');

  List<File> filesIn(String name) {
    final dir = workDir(name);
    if (!dir.existsSync()) return [];
    return dir.listSync(recursive: true).whereType<File>().toList();
  }

  setUpAll(() async {
    ocr = await createPlatformOcrServices(
      registry: OcrLanguagePackRegistry.standard,
      logger: const DebugAppLogger(),
    );
    pdf = await createPlatformPdfServices(logger: const DebugAppLogger());
    cache = await getTemporaryDirectory();
    final support = await getApplicationSupportDirectory();
    out = Directory('${support.path}/pdf_it')..createSync(recursive: true);
    work = Directory('${cache.path}/pdf_it_in')..createSync(recursive: true);
    greekPage = await renderDocument(greekReceipt.lines);
    latinPage = await renderDocument(latinAccents.lines);
  });

  tearDownAll(() async {
    await ocr.engine.dispose();
    await ocr.workStore.purgeAll();
    await pdf.builder.purgeAll();
    if (work.existsSync()) work.deleteSync(recursive: true);
    // Time for the runner to pull the last files.
    await Future<void>.delayed(const Duration(seconds: 7));
  });

  /// The engine-level path: reads [paths] with [engine] and builds the PDF.
  Future<(BuiltPdf, List<PdfPageInput>)> makePdf(
    List<String> paths, {
    String packId = OcrPackIds.greek,
    OcrEngine? engine,
    FutureOr<void> Function(OcrSession session)? beforeClose,
  }) async {
    final recognize = RecognizePages(
      engine: engine ?? ocr.engine,
      workStore: ocr.workStore,
      prepare: PrepareImageForOcr(
        headerReader: ocr.headerReader,
        dartMaker: ocr.dartMaker,
        nativeMaker: ocr.nativeMaker,
        workStore: ocr.workStore,
      ),
    );
    final session = recognize.start(packId: packId);
    for (final p in paths) {
      session.add(p, p);
    }
    await beforeClose?.call(session);
    session.close();
    final done = await session.finished;
    final inputs = [
      for (final page in done.pages)
        PdfPageInput(image: page.image!, outcome: page.outcome!),
    ];
    final built = await pdf.builder.build(inputs);
    // Working copies of the session go away like they do after the PDF.
    await session.dispose();
    return (built, inputs);
  }

  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 150),
  }) async {
    final end = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) fail('Timed out waiting for $finder');
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  group('the screen flow (real OCR, real PDF writer)', () {
    late DirectoryScanFileStore folder;
    late FakeOpenPdf opener;

    Future<void> startApp(WidgetTester tester, List<img.Image> pages) async {
      final shots = Directory('${work.path}/shots')
        ..createSync(recursive: true);
      folder = DirectoryScanFileStore(
        Directory('${work.path}/user_folder')..createSync(recursive: true),
      );
      opener = FakeOpenPdf();
      final container = await buildTestContainer(
        camera: _SyntheticCamera(shots, pages),
        scanFileStore: folder,
        scanTempStore: FakeScanTempStore(),
        ocr: ocr,
        pdf: PdfServices(builder: pdf.builder, opener: opener),
      );
      final repository = container<SettingsRepository>();
      await repository.save(
        (await repository.load()).copyWith(
          firstRunCompleted: true,
          storageFolder: testFolder,
          ocrPackId: OcrPackIds.greek,
        ),
      );
      await tester.pumpWidget(OneClickScanApp(container: container));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(HomeKeys.scanAndSend));
      await tester.pumpAndSettle();
    }

    tearDown(() {
      final dir = Directory('${work.path}/user_folder');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      final shots = Directory('${work.path}/shots');
      if (shots.existsSync()) shots.deleteSync(recursive: true);
    });

    testWidgets('one page: ./pdf/<stem>.pdf next to ./pictures, text layer, '
        'cache cleaned', (tester) async {
      await startApp(tester, [greekPage]);

      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pump();
      // While the text is read: text only, no spinner.
      await pumpUntil(tester, find.byKey(ScanKeys.pdfOpen));
      expect(find.byType(CircularProgressIndicator), findsNothing);

      expect(folder.files('pdf'), ['2026-10-21_19-05-12.pdf']);
      expect(folder.files('pictures').where((f) => f.endsWith('.jpg')), [
        '2026-10-21_19-05-12_1.jpg',
      ]);
      expect(find.text('PDF saved: 2026-10-21_19-05-12.pdf'), findsOneWidget);

      final pdfPath = '${folder.root.path}/pdf/2026-10-21_19-05-12.pdf';
      final inspected = PdfInspector(File(pdfPath).readAsBytesSync());
      report(
        'flow 1 page: ${File(pdfPath).lengthSync()} bytes, '
        '${inspected.invisibleTextCount} words',
      );
      if (inspected.invisibleTextCount == 0) {
        // Diagnostics: what did the reading say about this page?
        await tester.tap(find.byKey(ScanKeys.resultOcr));
        await tester.pumpAndSettle();
        final failure = find.byKey(OcrKeys.failure);
        report(
          'no text; check screen failure: '
          '${failure.evaluate().isEmpty ? 'none' : (tester.widget<Text>(failure).data)}, '
          'noText ${find.byKey(OcrKeys.noText).evaluate().isNotEmpty}',
        );
      }
      expect(inspected.pageCount, 1);
      expect(inspected.imageCount, 1);
      expect(inspected.invisibleTextCount, greaterThan(20));
      expect(inspected.visibleTextCount, 0);
      expect(inspected.toUnicodeCharacters, containsAll(['Π', 'Α', 'ά', 'ύ']));
      await keep(pdfPath, 'flow_1page.pdf');

      // The pictures of the user's documents are not left in the cache.
      expect(filesIn('ocr_work'), isEmpty);
      expect(filesIn('pdf_work'), isEmpty);

      // The button hands the stored file to the viewer.
      await tester.tap(find.byKey(ScanKeys.pdfOpen));
      await tester.pump();
      expect(opener.opened, hasLength(1));
      expect(opener.opened.single, endsWith('2026-10-21_19-05-12.pdf'));

      // The OCR check screen is still there and still has the text.
      await tester.tap(find.byKey(ScanKeys.resultOcr));
      await tester.pumpAndSettle();
      expect(find.textContaining('45,90'), findsWidgets);
    });

    testWidgets('three pages: ONE pdf with 3 pages, named after the first '
        'page', (tester) async {
      await startApp(tester, [greekPage, latinPage, greekPage]);
      await tester.tap(find.text('Multi page'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(ScanKeys.capture));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(ScanKeys.done));
      await tester.pump();

      await pumpUntil(tester, find.byKey(ScanKeys.pdfOpen));

      expect(folder.files('pdf'), ['2026-10-21_19-05-12.pdf']);
      expect(
        folder.files('pictures').where((f) => f.endsWith('.jpg')).toList()
          ..sort(),
        [
          '2026-10-21_19-05-12_1.jpg',
          '2026-10-21_19-05-12_2.jpg',
          '2026-10-21_19-05-12_3.jpg',
        ],
      );
      final pdfPath = '${folder.root.path}/pdf/2026-10-21_19-05-12.pdf';
      final inspected = PdfInspector(File(pdfPath).readAsBytesSync());
      report(
        'flow 3 pages: ${File(pdfPath).lengthSync()} bytes, '
        '${inspected.invisibleTextCount} words',
      );
      expect(inspected.pageCount, 3);
      expect(inspected.imageCount, 3);
      expect(inspected.invisibleTextCount, greaterThan(40));
      expect(find.textContaining('3 pages,'), findsOneWidget);
      await keep(pdfPath, 'flow_3pages.pdf');
      expect(filesIn('ocr_work'), isEmpty);
      expect(filesIn('pdf_work'), isEmpty);
    });

    testWidgets('a second scan after the first gets the next free name', (
      tester,
    ) async {
      await startApp(tester, [greekPage]);
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pump();
      await pumpUntil(tester, find.byKey(ScanKeys.pdfOpen));
      expect(folder.files('pdf'), ['2026-10-21_19-05-12.pdf']);

      await tester.tap(find.byKey(ScanKeys.resultBack));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(HomeKeys.scanAndSend));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pump();
      await pumpUntil(tester, find.byKey(ScanKeys.pdfOpen));

      // The test clock does not move, so the stem collides and gets -2.
      expect(folder.files('pdf')..sort(), [
        '2026-10-21_19-05-12-2.pdf',
        '2026-10-21_19-05-12.pdf',
      ]);
      expect(
        folder.files('pictures').where((f) => f.endsWith('.jpg')).toList()
          ..sort(),
        ['2026-10-21_19-05-12-2_1.jpg', '2026-10-21_19-05-12_1.jpg'],
      );
    });

    testWidgets('the folder refuses the PDF: clear message, photos intact, '
        'no crash, then Try again works', (tester) async {
      await startApp(tester, [greekPage]);
      folder.failSubfolder = 'pdf';

      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pump();
      await pumpUntil(tester, find.byKey(ScanKeys.pdfFailure));

      expect(
        find.textContaining('could not be written to your folder'),
        findsOneWidget,
      );
      expect(find.text('Scan saved'), findsOneWidget);
      expect(folder.files('pictures').where((f) => f.endsWith('.jpg')), [
        '2026-10-21_19-05-12_1.jpg',
      ]);
      expect(folder.files('pdf'), isEmpty);
      // The PDF in the cache is gone even though it was not stored.
      expect(filesIn('pdf_work'), isEmpty);

      folder.failSubfolder = null;
      await tester.tap(find.byKey(ScanKeys.pdfRetry));
      await pumpUntil(tester, find.byKey(ScanKeys.pdfOpen));
      expect(folder.files('pdf'), ['2026-10-21_19-05-12.pdf']);
      expect(filesIn('ocr_work'), isEmpty);
    });

    testWidgets('no access to the folder is said clearly', (tester) async {
      await startApp(tester, [greekPage]);
      folder
        ..failSubfolder = 'pdf'
        ..failure = ScanStoreFailure.noAccess;

      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pump();
      await pumpUntil(tester, find.byKey(ScanKeys.pdfFailure));

      expect(
        find.textContaining('no longer has access to your folder'),
        findsOneWidget,
      );
      expect(
        folder.files('pictures').where((f) => f.endsWith('.jpg')),
        isNotEmpty,
      );
    });
  });

  group('the PDF of the engine (real models)', () {
    testWidgets('Greek + English: words with their places, Unicode in the '
        'file', (tester) async {
      final file = writeJpeg('${work.path}/greek.jpg', greekPage);

      final (built, inputs) = await makePdf([file.path]);

      final result = (inputs.single.outcome as OcrSuccess).result;
      final withBoxes = result.lines.where((l) => l.charBoxes != null).length;
      report(
        'engine greek: ${result.boxCount} boxes, $withBoxes with character '
        'boxes, PDF ${built.byteSize} bytes in ${built.duration.inMilliseconds} '
        'ms, picture ${File(inputs.single.image.path).existsSync() ? 'kept' : 'gone'}',
      );
      // Every line the engine returns has character boxes that add up.
      expect(withBoxes, result.boxCount);
      for (final line in result.lines) {
        expect(line.charBoxes!.map((b) => b.character).join(), line.text);
        for (final box in line.charBoxes!) {
          for (final p in box.quad) {
            expect(p.x, inInclusiveRange(0.0, 1.0));
            expect(p.y, inInclusiveRange(0.0, 1.0));
          }
        }
      }
      expect(built.textPageCount, 1);
      final inspected = PdfInspector(File(built.path).readAsBytesSync());
      expect(inspected.invisibleTextCount, greaterThan(20));
      await keep(built.path, 'engine_greek.pdf');
      await pdf.builder.discard(built.path);
    });

    testWidgets('Latin with accents', (tester) async {
      final file = writeJpeg('${work.path}/latin.jpg', latinPage);

      final (built, inputs) = await makePdf([
        file.path,
      ], packId: OcrPackIds.latin);

      final result = (inputs.single.outcome as OcrSuccess).result;
      report(
        'engine latin: ${result.boxCount} boxes, PDF ${built.byteSize} bytes '
        'in ${built.duration.inMilliseconds} ms',
      );
      final inspected = PdfInspector(File(built.path).readAsBytesSync());
      expect(inspected.toUnicodeCharacters, containsAll(['ü', 'ß', 'é', 'ñ']));
      await keep(built.path, 'engine_latin.pdf');
      await pdf.builder.discard(built.path);
    });

    testWidgets('EXIF orientation 6: the PDF page is upright', (tester) async {
      // Stored the way a camera would (rotated pixels + tag 6).
      final stored = storedFor(greekPage, 6);
      final file = writeJpeg(
        '${work.path}/exif6.jpg',
        stored,
        exifOrientation: 6,
      );
      expect(stored.height, greaterThan(stored.width)); // portrait on disk

      final (built, inputs) = await makePdf([file.path]);

      final upright = inputs.single.image;
      expect(upright.width, greaterThan(upright.height)); // landscape page
      final inspected = PdfInspector(File(built.path).readAsBytesSync());
      final box = inspected.mediaBoxes.single;
      expect(box.$1, closeTo(upright.width * 0.36, 0.5));
      expect(box.$2, closeTo(upright.height * 0.36, 0.5));
      expect(box.$1, greaterThan(box.$2));
      final result = (inputs.single.outcome as OcrSuccess).result;
      expect(keyRecall(result.text, greekReceipt.keyTokens), greaterThan(0.9));
      report(
        'exif 6: page ${box.$1.toStringAsFixed(1)} x '
        '${box.$2.toStringAsFixed(1)} pt, PDF ${built.byteSize} bytes',
      );
      await keep(built.path, 'engine_exif6.pdf');
      await pdf.builder.discard(built.path);
    });

    testWidgets('a 12 MP photo of the page (native decode): PDF made, size '
        'noted', (tester) async {
      final file = writeBigPhoto(work.path, greekPage);

      final (built, inputs) = await makePdf([file.path]);

      final upright = inputs.single.image;
      report(
        'big photo ${upright.sourceWidth}x${upright.sourceHeight} -> '
        '${upright.width}x${upright.height}: PDF ${built.byteSize} bytes, '
        'photo file ${file.lengthSync()} bytes, '
        'write ${built.duration.inMilliseconds} ms',
      );
      expect(built.pageCount, 1);
      expect(built.byteSize, lessThan(file.lengthSync() * 2));
      await keep(built.path, 'engine_bigphoto.pdf');
      await pdf.builder.discard(built.path);
    });

    testWidgets('a page of scribbles: low confidence lines are not written, '
        'the PDF is made', (tester) async {
      final file = writeJpeg(
        '${work.path}/scribbles.jpg',
        await renderScribbles(),
      );

      final (built, inputs) = await makePdf([file.path]);

      final outcome = inputs.single.outcome;
      final inspected = PdfInspector(File(built.path).readAsBytesSync());
      report(
        'scribbles: outcome ${outcome.runtimeType}, words '
        '${inspected.invisibleTextCount}, text pages ${built.textPageCount}',
      );
      expect(inspected.pageCount, 1);
      expect(inspected.imageCount, 1);
      if (outcome is OcrSuccess) {
        final kept = outcome.result.visibleLines.length;
        expect(built.textPageCount, kept == 0 ? 0 : 1);
      }
      await pdf.builder.discard(built.path);
    });

    testWidgets('three pages: one PDF in capture order', (tester) async {
      final a = writeJpeg('${work.path}/a.jpg', greekPage);
      final b = writeJpeg('${work.path}/b.jpg', latinPage);
      final c = writeJpeg('${work.path}/c.jpg', greekPage);

      final (built, _) = await makePdf([a.path, b.path, c.path]);

      expect(built.pageCount, 3);
      expect(built.textPageCount, 3);
      report(
        '3 pages engine: PDF ${built.byteSize} bytes in '
        '${built.duration.inMilliseconds} ms',
      );
      await keep(built.path, 'engine_3pages.pdf');
      await pdf.builder.discard(built.path);
    });
  });

  group('no text when the reading is stopped, and the next scan is fine', () {
    testWidgets('a timeout: the PDF has the picture and no text; the next '
        'scan reads normally', (tester) async {
      final file = writeJpeg('${work.path}/t.jpg', greekPage);

      final (built, inputs) = await makePdf([
        file.path,
      ], engine: _ShortTimeoutEngine(ocr.engine));

      expect(inputs.single.outcome, isA<OcrTimedOut>());
      expect(built.pageCount, 1);
      expect(built.textPageCount, 0);
      final inspected = PdfInspector(File(built.path).readAsBytesSync());
      expect(inspected.imageCount, 1);
      expect(inspected.invisibleTextCount, 0);
      report('timeout: PDF ${built.byteSize} bytes, no text');
      await keep(built.path, 'engine_timeout.pdf');
      await pdf.builder.discard(built.path);

      // The worker may still be finishing the timed out page: the next scan
      // waits for it and reads fine.
      final next = await makePdf([file.path]);
      expect(next.$1.textPageCount, 1);
      await pdf.builder.discard(next.$1.path);
    });

    testWidgets('cancelled while recognizing: PDF without text, next scan '
        'fine', (tester) async {
      final file = writeJpeg('${work.path}/c1.jpg', greekPage);

      final (built, inputs) = await makePdf(
        [file.path, file.path],
        beforeClose: (session) async {
          // Wait until the first page is being read, then stop the reading.
          final end = DateTime.now().add(const Duration(seconds: 60));
          while (session.snapshot.pages.first.status !=
                  OcrPageStatus.recognizing &&
              DateTime.now().isBefore(end)) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          session.stopReading();
        },
      );

      expect(inputs.map((p) => p.outcome), everyElement(isA<OcrCancelled>()));
      expect(built.pageCount, 2);
      expect(built.textPageCount, 0);
      await pdf.builder.discard(built.path);

      final next = await makePdf([file.path]);
      expect(next.$1.textPageCount, 1);
      await pdf.builder.discard(next.$1.path);
    });

    testWidgets('the screen: skip the text, the PDF is made at once', (
      tester,
    ) async {
      final shots = Directory('${work.path}/shots2')
        ..createSync(recursive: true);
      final folder = DirectoryScanFileStore(
        Directory('${work.path}/user_folder2')..createSync(recursive: true),
      );
      final container = await buildTestContainer(
        camera: _SyntheticCamera(shots, [greekPage, greekPage]),
        scanFileStore: folder,
        scanTempStore: FakeScanTempStore(),
        ocr: OcrServices(
          engine: _SlowEngine(ocr.engine),
          workStore: ocr.workStore,
          headerReader: ocr.headerReader,
          dartMaker: ocr.dartMaker,
          nativeMaker: ocr.nativeMaker,
        ),
        pdf: PdfServices(builder: pdf.builder, opener: FakeOpenPdf()),
      );
      final repository = container<SettingsRepository>();
      await repository.save(
        (await repository.load()).copyWith(
          firstRunCompleted: true,
          storageFolder: testFolder,
          ocrPackId: OcrPackIds.greek,
        ),
      );
      await tester.pumpWidget(OneClickScanApp(container: container));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(HomeKeys.scanAndSend));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Multi page'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ScanKeys.done));
      await tester.pump();

      await pumpUntil(tester, find.byKey(ScanKeys.pdfSkipText));
      await tester.tap(find.byKey(ScanKeys.pdfSkipText));
      await pumpUntil(tester, find.byKey(ScanKeys.pdfOpen));

      expect(
        find.text(
          '2 pages have no searchable text. Their pictures are in the PDF.',
        ),
        findsOneWidget,
      );
      expect(folder.files('pdf'), hasLength(1));
      expect(filesIn('ocr_work'), isEmpty);
      Directory('${work.path}/user_folder2').deleteSync(recursive: true);
      shots.deleteSync(recursive: true);
    });
  });
}

/// A camera whose shots are real JPEG files of invented pages.
class _SyntheticCamera extends FakeCameraService {
  _SyntheticCamera(this.dir, this.pages);

  final Directory dir;
  final List<img.Image> pages;
  var _n = 0;

  @override
  Future<CapturedPage> capture({required int order}) async {
    final page = pages[_n % pages.length];
    final file = writeJpeg('${dir.path}/shot_${_n++}.jpg', page);
    return CapturedPage(path: file.path, order: order);
  }
}

/// The real engine with a time limit so short that the page always times out
/// (the limit of the page is 45 s; a test cannot wait for it).
class _ShortTimeoutEngine implements OcrEngine {
  _ShortTimeoutEngine(this.inner);

  final OcrEngine inner;

  @override
  Future<void> preload(String packId) => inner.preload(packId);

  @override
  Future<OcrOutcome> recognize(
    UprightImage image, {
    required String packId,
    Duration timeout = const Duration(seconds: 45),
    OcrCancellation? cancellation,
    void Function(OcrProgress progress)? onProgress,
  }) => inner.recognize(
    image,
    packId: packId,
    timeout: const Duration(milliseconds: 5),
    cancellation: cancellation,
    onProgress: onProgress,
  );

  @override
  Future<void> release() => inner.release();

  @override
  Future<void> dispose() async {}
}

/// The real engine, held back for a few seconds before each page so the test
/// can press "skip" while the text is still being read.
class _SlowEngine implements OcrEngine {
  _SlowEngine(this.inner);

  final OcrEngine inner;

  @override
  Future<void> preload(String packId) => inner.preload(packId);

  @override
  Future<OcrOutcome> recognize(
    UprightImage image, {
    required String packId,
    Duration timeout = const Duration(seconds: 45),
    OcrCancellation? cancellation,
    void Function(OcrProgress progress)? onProgress,
  }) async {
    await Future.any([
      Future<void>.delayed(const Duration(seconds: 20)),
      ?cancellation?.whenCancelled,
    ]);
    if (cancellation?.isCancelled ?? false) return const OcrCancelled();
    return inner.recognize(
      image,
      packId: packId,
      timeout: timeout,
      cancellation: cancellation,
      onProgress: onProgress,
    );
  }

  @override
  Future<void> release() => inner.release();

  @override
  Future<void> dispose() async {}
}
