import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/core/errors/app_exceptions.dart';
import 'package:one_click_scan/data/datasources/key_value_gallery_counter_store.dart';
import 'package:one_click_scan/domain/entities/captured_page.dart';
import 'package:one_click_scan/domain/entities/stored_scan.dart';
import 'package:one_click_scan/domain/scan/gallery_naming.dart';
import 'package:one_click_scan/domain/scan/scan_naming.dart';
import 'package:one_click_scan/domain/usecases/store_scan_pages.dart';

import '../support/fakes.dart';
import '../support/scan_fakes.dart';

void main() {
  late FakeScanFileStore store;
  late FakeGalleryService gallery;
  late RecordingLogger logger;
  late StoreScanPages useCase;

  const pages = [
    CapturedPage(path: 'cache/a.jpg', order: 1),
    CapturedPage(path: 'cache/b.jpg', order: 2),
  ];

  setUp(() {
    store = FakeScanFileStore();
    gallery = FakeGalleryService();
    logger = RecordingLogger();
    useCase = StoreScanPages(
      fileStore: store,
      gallery: gallery,
      naming: ScanNaming(() => DateTime(2026, 10, 21, 19, 5, 12)),
      galleryNaming: GalleryNaming(() => DateTime(2026, 10, 21, 19, 5, 12)),
      galleryCounter: KeyValueGalleryCounterStore(InMemoryKeyValueStore()),
      logger: logger,
    );
  });

  Future<StoredScan> run({bool gallery = false, List<CapturedPage>? input}) {
    return useCase(
      pages: input ?? pages,
      folder: testFolder,
      saveToGallery: gallery,
    );
  }

  test('stores the pages under ./pictures with a shared stem', () async {
    final result = await run();

    expect(result.stem, '2026-10-21_19-05-12');
    expect(result.pictures.map((p) => p.fileName), [
      '2026-10-21_19-05-12_1.jpg',
      '2026-10-21_19-05-12_2.jpg',
    ]);
    expect(store.files('pictures'), [
      '2026-10-21_19-05-12_1.jpg',
      '2026-10-21_19-05-12_2.jpg',
    ]);
  });

  group('what a discard needs (ADR-027)', () {
    test('every picture records the URI of its file in the folder', () async {
      final result = await run();

      expect(result.pictures.map((p) => p.uri), [
        'content://com.example.test/tree/Scans/document/pictures%2F2026-10-21_19-05-12_1.jpg',
        'content://com.example.test/tree/Scans/document/pictures%2F2026-10-21_19-05-12_2.jpg',
      ]);
      expect(result.pictures.every((p) => p.galleryUri == null), isTrue);
    });

    test('every saved Gallery copy records its own URI', () async {
      final result = await run(gallery: true);

      expect(result.pictures.map((p) => p.galleryUri), [
        'content://media/external/images/media/1',
        'content://media/external/images/media/2',
      ]);
    });

    test('a failed Gallery copy records no URI', () async {
      gallery.fail = true;

      final result = await run(gallery: true);

      expect(
        result.pictures.every(
          (p) => p.gallery == GalleryCopyStatus.failed && p.galleryUri == null,
        ),
        isTrue,
      );
      expect(result.pictures.every((p) => p.uri != null), isTrue);
    });
  });

  group('.nomedia marker', () {
    test('is created before the first picture is copied', () async {
      await run();

      expect(store.noMedia, {'pictures'});
      expect(store.calls.first, 'subfolder:pictures');
      expect(store.calls.indexOf('noMedia:pictures'), lessThan(2));
      expect(
        store.calls.indexOf('noMedia:pictures'),
        lessThan(store.calls.indexWhere((c) => c.startsWith('copy:'))),
      );
    });

    test('is created whether or not the Gallery copy is requested', () async {
      await run(gallery: false);
      expect(store.noMedia, {'pictures'});

      store.noMedia.clear();
      await run(gallery: true);
      expect(store.noMedia, {'pictures'});
      expect(gallery.saved, hasLength(2));
    });

    test('a failure is logged and the scan still succeeds', () async {
      store.failNoMedia = true;
      final result = await run();

      expect(result.pictures, hasLength(2));
      expect(store.files('pictures'), hasLength(2));
      expect(logger.messages, contains('Could not hide the pictures folder'));
    });

    test('an existing marker does not disturb the numbering', () async {
      store.folders['pictures'] = ['.nomedia'];
      final result = await run();

      expect(result.stem, '2026-10-21_19-05-12');
      expect(result.pictures.first.fileName, '2026-10-21_19-05-12_1.jpg');
    });
  });

  test('pages are numbered by their order, not by list position', () async {
    final result = await run(input: [pages[1], pages[0]]);

    expect(result.pictures.map((p) => p.sourcePath), [
      'cache/a.jpg',
      'cache/b.jpg',
    ]);
  });

  test('a stem already in the folder gets a suffix', () async {
    store.folders['pictures'] = ['2026-10-21_19-05-12_1.jpg'];

    final result = await run();

    expect(result.stem, '2026-10-21_19-05-12-2');
    expect(store.files('pictures'), contains('2026-10-21_19-05-12-2_2.jpg'));
  });

  test('no Gallery copy when the switch is off', () async {
    final result = await run();

    expect(gallery.saved, isEmpty);
    expect(
      result.pictures.every((p) => p.gallery == GalleryCopyStatus.notRequested),
      isTrue,
    );
  });

  test('Gallery copies are made when the switch is on', () async {
    final result = await run(gallery: true);

    expect(gallery.saved, ['cache/a.jpg', 'cache/b.jpg']);
    expect(
      result.pictures.every((p) => p.gallery == GalleryCopyStatus.saved),
      isTrue,
    );
  });

  test(
    'a failing Gallery copy is a partial result, not a failed scan',
    () async {
      gallery.fail = true;

      final result = await run(gallery: true);

      expect(store.files('pictures'), hasLength(2));
      expect(result.hasGalleryFailures, isTrue);
      expect(
        result.pictures.every((p) => p.gallery == GalleryCopyStatus.failed),
        isTrue,
      );
    },
  );

  test('a failing store removes what was written and rethrows', () async {
    store.failOnCopyNumber = 2;

    await expectLater(
      run(gallery: true),
      throwsA(
        isA<ScanStoreException>().having(
          (e) => e.failure,
          'failure',
          ScanStoreFailure.writeFailed,
        ),
      ),
    );

    expect(store.files('pictures'), isEmpty);
    expect(store.deleted, ['2026-10-21_19-05-12_1.jpg']);
    expect(gallery.saved, isEmpty);
  });

  test('a retry after a failure starts clean with the same stem', () async {
    store.failOnCopyNumber = 2;
    await expectLater(run(), throwsA(isA<ScanStoreException>()));

    store.failOnCopyNumber = null;
    final result = await run();

    expect(result.stem, '2026-10-21_19-05-12');
    expect(store.files('pictures'), hasLength(2));
  });

  test('empty input is rejected', () async {
    await expectLater(run(input: const []), throwsArgumentError);
  });

  test('logs never contain file names', () async {
    gallery.fail = true;
    await run(gallery: true);

    expect(logger.messages.join(), isNot(contains('.jpg')));
  });

  group('Gallery names', () {
    late InMemoryKeyValueStore values;
    late DateTime now;

    StoreScanPages build([InMemoryKeyValueStore? counterValues]) =>
        StoreScanPages(
          fileStore: store,
          gallery: gallery,
          naming: ScanNaming(() => now),
          galleryNaming: GalleryNaming(() => now),
          galleryCounter: KeyValueGalleryCounterStore(counterValues ?? values),
          logger: logger,
        );

    setUp(() {
      values = InMemoryKeyValueStore();
      now = DateTime(2026, 10, 21, 19, 5, 12);
      useCase = build();
    });

    test('one page gets scan_<date>_01.jpg', () async {
      await run(gallery: true, input: [pages.first]);

      expect(gallery.savedNames, ['scan_2026-10-21_01.jpg']);
    });

    test('several pages take consecutive numbers', () async {
      await run(gallery: true);

      expect(gallery.savedNames, [
        'scan_2026-10-21_01.jpg',
        'scan_2026-10-21_02.jpg',
      ]);
    });

    test('the next scan of the day continues the numbering', () async {
      await run(gallery: true, input: [pages.first]);
      await run(gallery: true);

      expect(gallery.savedNames, [
        'scan_2026-10-21_01.jpg',
        'scan_2026-10-21_02.jpg',
        'scan_2026-10-21_03.jpg',
      ]);
    });

    test('the numbering survives a new use case instance (restart)', () async {
      await run(gallery: true, input: [pages.first]);
      useCase = build();
      await run(gallery: true, input: [pages.first]);

      expect(gallery.savedNames.last, 'scan_2026-10-21_02.jpg');
    });

    test('a new day starts again at 01', () async {
      await run(gallery: true);
      now = DateTime(2026, 10, 22, 8, 0, 0);
      await run(gallery: true, input: [pages.first]);

      expect(gallery.savedNames.last, 'scan_2026-10-22_01.jpg');
    });

    test('the day can change in the middle of a scan', () async {
      now = DateTime(2026, 10, 21, 23, 59, 59);
      gallery.onSave = () => now = DateTime(2026, 10, 22, 0, 0, 1);
      await run(gallery: true);

      expect(gallery.savedNames, [
        'scan_2026-10-21_01.jpg',
        'scan_2026-10-22_01.jpg',
      ]);
    });

    test('a failing copy does not use a number up', () async {
      gallery.fail = true;
      await run(gallery: true, input: [pages.first]);
      expect(gallery.savedNames, isEmpty);

      gallery.fail = false;
      await run(gallery: true, input: [pages.first]);
      expect(gallery.savedNames, ['scan_2026-10-21_01.jpg']);
    });

    test('with the switch off no number is used', () async {
      await run(gallery: false);
      await run(gallery: true, input: [pages.first]);

      expect(gallery.savedNames, ['scan_2026-10-21_01.jpg']);
    });

    test('the originals in ./pictures keep their own names', () async {
      final result = await run(gallery: true);

      expect(result.pictures.map((p) => p.fileName), [
        '2026-10-21_19-05-12_1.jpg',
        '2026-10-21_19-05-12_2.jpg',
      ]);
    });

    test('a counter that cannot be saved is logged, the copy stays', () async {
      useCase = build(_FailingWriteStore());

      final result = await run(gallery: true, input: [pages.first]);

      expect(result.pictures.single.gallery, GalleryCopyStatus.saved);
      expect(logger.messages, contains('Gallery counter not saved'));
    });
  });
}

class _FailingWriteStore extends InMemoryKeyValueStore {
  @override
  Future<void> setInt(String key, int value) async {
    throw StateError('disk full');
  }
}
