import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/core/logging/app_logger.dart';
import 'package:one_click_scan/domain/entities/pdf_page_input.dart';
import 'package:one_click_scan/domain/entities/stored_scan.dart';
import 'package:one_click_scan/domain/usecases/discard_scan.dart';

import '../../support/scan_fakes.dart';

class _SilentLogger implements AppLogger {
  @override
  void debug(String message) {}

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {}
}

String _uri(String subfolder, String name) =>
    'content://com.example.test/tree/Scans/document/$subfolder%2F$name';

void main() {
  late FakeScanFileStore store;
  late FakeGalleryService gallery;
  late DiscardScan discard;

  StoredPicture picture(
    int n, {
    GalleryCopyStatus status = GalleryCopyStatus.saved,
    bool withGalleryUri = true,
  }) => StoredPicture(
    fileName: 's_$n.jpg',
    sourcePath: 'cache/$n.jpg',
    uri: _uri('pictures', 's_$n.jpg'),
    gallery: status,
    galleryUri: status == GalleryCopyStatus.saved && withGalleryUri
        ? 'content://media/external/images/media/$n'
        : null,
  );

  final pdf = StoredPdf(
    fileName: 's.pdf',
    uri: _uri('pdf', 's.pdf'),
    pageCount: 2,
    textPageCount: 2,
    byteSize: 1000,
  );

  setUp(() {
    store = FakeScanFileStore()
      ..folders['pictures'] = ['s_1.jpg', 's_2.jpg', 'other_scan_1.jpg']
      ..folders['pdf'] = ['s.pdf', 'other_scan.pdf'];
    gallery = FakeGalleryService();
    discard = DiscardScan(
      fileStore: store,
      gallery: gallery,
      logger: _SilentLogger(),
    );
  });

  test('deletes the pictures, the PDF and the Gallery copies', () async {
    final scan = StoredScan(stem: 's', pictures: [picture(1), picture(2)]);

    final outcome = await discard(scan: scan, pdf: pdf);

    expect(outcome.complete, isTrue);
    expect(store.files('pictures'), ['other_scan_1.jpg']);
    expect(store.files('pdf'), ['other_scan.pdf']);
    expect(gallery.deletedUris, [
      'content://media/external/images/media/1',
      'content://media/external/images/media/2',
    ]);
  });

  test('deletes only by the recorded URIs: nothing else is touched', () async {
    final scan = StoredScan(stem: 's', pictures: [picture(1)]);

    await discard(scan: scan, pdf: pdf);

    expect(store.deletedUris, [
      _uri('pdf', 's.pdf'),
      _uri('pictures', 's_1.jpg'),
    ]);
    // Never by name or by folder.
    expect(store.deleted, isEmpty);
    expect(
      store.files('pictures'),
      containsAll(['s_2.jpg', 'other_scan_1.jpg']),
    );
    expect(store.files('pdf'), ['other_scan.pdf']);
  });

  test('no PDF yet (it could not be made): only the pictures go', () async {
    final scan = StoredScan(stem: 's', pictures: [picture(1)]);

    final outcome = await discard(scan: scan);

    expect(outcome.complete, isTrue);
    expect(store.files('pdf'), ['s.pdf', 'other_scan.pdf']);
  });

  test('no Gallery copy was made: the Gallery is not touched', () async {
    final scan = StoredScan(
      stem: 's',
      pictures: [picture(1, status: GalleryCopyStatus.notRequested)],
    );

    final outcome = await discard(scan: scan, pdf: pdf);

    expect(outcome.complete, isTrue);
    expect(gallery.deletedUris, isEmpty);
  });

  test('a failed Gallery copy has nothing to delete there', () async {
    final scan = StoredScan(
      stem: 's',
      pictures: [picture(1, status: GalleryCopyStatus.failed)],
    );

    final outcome = await discard(scan: scan, pdf: pdf);

    expect(outcome.complete, isTrue);
    expect(gallery.deletedUris, isEmpty);
  });

  group('part of it stays: never reported as done', () {
    test('a picture that cannot be deleted', () async {
      final scan = StoredScan(stem: 's', pictures: [picture(1), picture(2)]);
      store.failDeleteUris.add(_uri('pictures', 's_1.jpg'));

      final outcome = await discard(scan: scan, pdf: pdf);

      expect(outcome.complete, isFalse);
      expect(outcome.picturesLeft, 1);
      expect(outcome.pdfLeft, isFalse);
      expect(outcome.galleryLeft, 0);
      // The others were still deleted.
      expect(store.files('pictures'), contains('s_1.jpg'));
      expect(store.files('pictures'), isNot(contains('s_2.jpg')));
      expect(store.files('pdf'), ['other_scan.pdf']);
    });

    test('the PDF cannot be deleted', () async {
      final scan = StoredScan(stem: 's', pictures: [picture(1)]);
      store.failDeleteUris.add(pdf.uri);

      final outcome = await discard(scan: scan, pdf: pdf);

      expect(outcome.complete, isFalse);
      expect(outcome.pdfLeft, isTrue);
      expect(outcome.picturesLeft, 0);
      expect(store.files('pictures'), isNot(contains('s_1.jpg')));
    });

    test('a Gallery copy cannot be deleted', () async {
      final scan = StoredScan(stem: 's', pictures: [picture(1), picture(2)]);
      gallery.failDeleteUris.add('content://media/external/images/media/2');

      final outcome = await discard(scan: scan, pdf: pdf);

      expect(outcome.complete, isFalse);
      expect(outcome.galleryLeft, 1);
      expect(outcome.picturesLeft, 0);
      expect(outcome.pdfLeft, isFalse);
    });

    test('a picture without a recorded URI counts as left', () async {
      const scan = StoredScan(
        stem: 's',
        pictures: [
          StoredPicture(fileName: 's_1.jpg', sourcePath: 'cache/1.jpg'),
        ],
      );

      final outcome = await discard(scan: scan, pdf: pdf);

      expect(outcome.picturesLeft, 1);
      expect(outcome.complete, isFalse);
      expect(store.files('pictures'), contains('s_1.jpg'));
    });

    test(
      'a saved Gallery copy without a URI counts as left, not guessed',
      () async {
        final scan = StoredScan(
          stem: 's',
          pictures: [picture(1, withGalleryUri: false)],
        );

        final outcome = await discard(scan: scan, pdf: pdf);

        expect(outcome.galleryLeft, 1);
        expect(gallery.deletedUris, isEmpty);
      },
    );

    test('everything fails: everything is counted', () async {
      final scan = StoredScan(stem: 's', pictures: [picture(1), picture(2)]);
      store.failDeleteUris
        ..add(pdf.uri)
        ..add(_uri('pictures', 's_1.jpg'))
        ..add(_uri('pictures', 's_2.jpg'));
      gallery.failDeleteUris
        ..add('content://media/external/images/media/1')
        ..add('content://media/external/images/media/2');

      final outcome = await discard(scan: scan, pdf: pdf);

      expect(outcome.picturesLeft, 2);
      expect(outcome.pdfLeft, isTrue);
      expect(outcome.galleryLeft, 2);
      expect(outcome.complete, isFalse);
    });
  });
}
