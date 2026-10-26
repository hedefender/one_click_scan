import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/core/errors/app_exceptions.dart';
import 'package:one_click_scan/data/datasources/key_value_gallery_counter_store.dart';
import 'package:one_click_scan/domain/entities/captured_page.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';
import 'package:one_click_scan/domain/entities/pdf_page_input.dart';
import 'package:one_click_scan/domain/entities/upright_image.dart';
import 'package:one_click_scan/domain/scan/gallery_naming.dart';
import 'package:one_click_scan/domain/scan/scan_naming.dart';
import 'package:one_click_scan/domain/usecases/store_scan_pages.dart';
import 'package:one_click_scan/domain/usecases/store_scan_pdf.dart';

import '../support/fakes.dart';
import '../support/ocr_fakes.dart';
import '../support/pdf_fakes.dart';
import '../support/scan_fakes.dart';

PdfPageInput pageWithText(String name) => PdfPageInput(
  image: UprightImage(
    path: 'work/$name.jpg',
    width: 1000,
    height: 1400,
    sourceWidth: 3000,
    sourceHeight: 4000,
  ),
  outcome: OcrSuccess(fakeResult([fakeLine('text of $name')])),
);

PdfPageInput pageWithoutText(String name) => PdfPageInput(
  image: UprightImage(
    path: 'work/$name.jpg',
    width: 1000,
    height: 1400,
    sourceWidth: 3000,
    sourceHeight: 4000,
  ),
  outcome: const OcrTimedOut(Duration(seconds: 45)),
);

void main() {
  late FakeScanFileStore store;
  late FakePdfBuilder builder;
  late RecordingLogger logger;
  late StoreScanPdf useCase;

  final clock = DateTime(2026, 10, 21, 19, 5, 12);

  setUp(() {
    store = FakeScanFileStore();
    builder = FakePdfBuilder();
    logger = RecordingLogger();
    useCase = StoreScanPdf(
      builder: builder,
      fileStore: store,
      naming: ScanNaming(() => clock),
      logger: logger,
    );
  });

  Future<StoredPdf> run(String stem, List<PdfPageInput> pages) =>
      useCase(folder: testFolder, stem: stem, pages: pages);

  group('name and place', () {
    test('one page: ./pdf/<stem>.pdf, the stem of the pictures', () async {
      final stored = await run('2026-10-21_19-05-12', [pageWithText('a')]);

      expect(stored.fileName, '2026-10-21_19-05-12.pdf');
      expect(store.files('pdf'), ['2026-10-21_19-05-12.pdf']);
      expect(stored.pageCount, 1);
      expect(stored.textPageCount, 1);
    });

    test('several pages: ONE pdf with the stem of the first page', () async {
      final stored = await run('2026-10-21_19-05-12', [
        pageWithText('a'),
        pageWithText('b'),
        pageWithoutText('c'),
      ]);

      // The pictures of that scan are <stem>_1.jpg, <stem>_2.jpg, ...: the PDF
      // has their stem, without a page number.
      expect(store.files('pdf'), ['2026-10-21_19-05-12.pdf']);
      expect(stored.pageCount, 3);
      expect(stored.textPageCount, 2);
      expect(stored.pagesWithoutText, 1);
    });

    test('the file goes to the pdf folder, not to pictures', () async {
      await run('2026-10-21_19-05-12', [pageWithText('a')]);

      expect(store.files('pictures'), isEmpty);
      expect(store.copies.single.$1, 'pdf');
      expect(store.copies.single.$2, '2026-10-21_19-05-12.pdf');
    });

    test('the sub-folder is created first and the URI is returned', () async {
      final stored = await run('2026-10-21_19-05-12', [pageWithText('a')]);

      expect(store.calls.first, 'subfolder:pdf');
      expect(stored.uri, contains('pdf%2F2026-10-21_19-05-12.pdf'));
    });

    test(
      'the copied file is the one the builder made, as application/pdf',
      () async {
        await run('s', [pageWithText('a')]);

        expect(store.copies.single.$3, 'pdf_work/fake_1.pdf');
      },
    );

    test('the size reported is the size of the file', () async {
      final stored = await run('s', [pageWithText('a')]);

      expect(stored.byteSize, 123456);
    });
  });

  group('collisions: an existing file is never replaced', () {
    test('a PDF with the same stem is already there: -2', () async {
      store.folders['pdf'] = ['2026-10-21_19-05-12.pdf'];

      final stored = await run('2026-10-21_19-05-12', [pageWithText('a')]);

      expect(stored.fileName, '2026-10-21_19-05-12-2.pdf');
      expect(store.files('pdf'), [
        '2026-10-21_19-05-12.pdf',
        '2026-10-21_19-05-12-2.pdf',
      ]);
    });

    test('-2 is taken too: -3', () async {
      store.folders['pdf'] = [
        '2026-10-21_19-05-12.pdf',
        '2026-10-21_19-05-12-2.pdf',
      ];

      final stored = await run('2026-10-21_19-05-12', [pageWithText('a')]);

      expect(stored.fileName, '2026-10-21_19-05-12-3.pdf');
    });

    test('other PDFs and other files do not matter', () async {
      store.folders['pdf'] = ['2026-10-20_08-00-00.pdf', 'notes.txt'];

      final stored = await run('2026-10-21_19-05-12', [pageWithText('a')]);

      expect(stored.fileName, '2026-10-21_19-05-12.pdf');
      expect(store.files('pdf'), hasLength(3));
    });

    test(
      'a file that appears after the listing: the next name is tried',
      () async {
        // The listing is empty, but the copy meets the name (a race).
        store.raceOnFirstCopy = ('pdf', '2026-10-21_19-05-12.pdf');

        final stored = await run('2026-10-21_19-05-12', [pageWithText('a')]);

        expect(stored.fileName, '2026-10-21_19-05-12-2.pdf');
        expect(store.files('pdf'), contains('2026-10-21_19-05-12.pdf'));
        expect(store.files('pdf'), contains('2026-10-21_19-05-12-2.pdf'));
      },
    );
  });

  group('the stem of the pictures is free in ./pdf as well', () {
    late StoreScanPages pages;

    setUp(() {
      pages = StoreScanPages(
        fileStore: store,
        gallery: FakeGalleryService(),
        naming: ScanNaming(() => clock),
        galleryNaming: GalleryNaming(() => clock),
        galleryCounter: KeyValueGalleryCounterStore(InMemoryKeyValueStore()),
        logger: logger,
      );
    });

    test('a PDF left from a deleted scan moves the new stem to -2', () async {
      // The pictures were deleted by the user, the PDF stayed.
      store.folders['pdf'] = ['2026-10-21_19-05-12.pdf'];

      final scan = await pages(
        pages: const [CapturedPage(path: 'cache/a.jpg', order: 1)],
        folder: testFolder,
        saveToGallery: false,
      );
      final stored = await run(scan.stem, [pageWithText('a')]);

      expect(scan.stem, '2026-10-21_19-05-12-2');
      expect(scan.pictures.single.fileName, '2026-10-21_19-05-12-2_1.jpg');
      // Pictures and PDF still match by name.
      expect(stored.fileName, '2026-10-21_19-05-12-2.pdf');
    });

    test('with nothing in ./pdf the stem is the plain one', () async {
      final scan = await pages(
        pages: const [CapturedPage(path: 'cache/a.jpg', order: 1)],
        folder: testFolder,
        saveToGallery: false,
      );

      expect(scan.stem, '2026-10-21_19-05-12');
    });
  });

  group('failures', () {
    test('the folder is not accessible: noAccess, nothing written', () async {
      store.failEverything = ScanStoreFailure.noAccess;

      await expectLater(
        run('s', [pageWithText('a')]),
        throwsA(
          isA<ScanPdfException>().having(
            (e) => e.failure,
            'failure',
            ScanPdfFailure.noAccess,
          ),
        ),
      );
      expect(store.files('pdf'), isEmpty);
    });

    test(
      'a write error (full storage): writeFailed, the cache PDF is deleted',
      () async {
        store.failSubfolder = 'pdf';

        await expectLater(
          run('s', [pageWithText('a')]),
          throwsA(
            isA<ScanPdfException>().having(
              (e) => e.failure,
              'failure',
              ScanPdfFailure.writeFailed,
            ),
          ),
        );
        expect(builder.discarded, ['pdf_work/fake_1.pdf']);
        expect(logger.messages, contains('Storing the PDF failed'));
      },
    );

    test(
      'the writer fails: the error comes through, nothing is stored',
      () async {
        builder.failWith = const ScanPdfException(ScanPdfFailure.buildFailed);

        await expectLater(
          run('s', [pageWithText('a')]),
          throwsA(
            isA<ScanPdfException>().having(
              (e) => e.failure,
              'failure',
              ScanPdfFailure.buildFailed,
            ),
          ),
        );
        expect(store.copyCalls, 0);
        expect(store.calls, isEmpty);
      },
    );

    test('after a success the cache PDF is deleted too', () async {
      await run('s', [pageWithText('a')]);

      expect(builder.discarded, ['pdf_work/fake_1.pdf']);
    });

    test('a failure never touches the pictures already stored', () async {
      store.folders['pictures'] = ['s_1.jpg', 's_2.jpg'];
      store.failSubfolder = 'pdf';

      await expectLater(
        run('s', [pageWithText('a')]),
        throwsA(isA<ScanPdfException>()),
      );

      expect(store.files('pictures'), ['s_1.jpg', 's_2.jpg']);
      expect(store.deleted, isEmpty);
    });

    test('no pages is a programming error', () {
      expect(() => run('s', const []), throwsArgumentError);
    });

    test('the log of a failure has no file names or text', () async {
      store.failSubfolder = 'pdf';

      await expectLater(
        run('2026-10-21_19-05-12', [pageWithText('secret')]),
        throwsA(isA<ScanPdfException>()),
      );

      final logged = logger.messages.join(' ');
      expect(logged, isNot(contains('secret')));
      expect(logged, isNot(contains('2026-10-21')));
    });
  });
}
