import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/data/datasources/key_value_gallery_counter_store.dart';
import 'package:one_click_scan/domain/scan/gallery_naming.dart';

import '../support/fakes.dart';

void main() {
  group('GalleryNaming', () {
    test('formats the device date without the time', () {
      final naming = GalleryNaming(() => DateTime(2026, 3, 7, 23, 59, 59));

      expect(naming.today(), '2026-03-07');
    });

    test('pads the number to two digits', () {
      const naming = GalleryNaming(DateTime.now);

      expect(naming.fileName('2026-10-21', 1), 'scan_2026-10-21_01.jpg');
      expect(naming.fileName('2026-10-21', 9), 'scan_2026-10-21_09.jpg');
      expect(naming.fileName('2026-10-21', 10), 'scan_2026-10-21_10.jpg');
    });

    test('has no upper limit at 99', () {
      const naming = GalleryNaming(DateTime.now);

      expect(naming.fileName('2026-10-21', 99), 'scan_2026-10-21_99.jpg');
      expect(naming.fileName('2026-10-21', 100), 'scan_2026-10-21_100.jpg');
      expect(naming.fileName('2026-10-21', 1234), 'scan_2026-10-21_1234.jpg');
    });

    test('follows the injected clock, so the day can change', () {
      var now = DateTime(2026, 12, 31, 23, 59);
      final naming = GalleryNaming(() => now);
      expect(naming.today(), '2026-12-31');

      now = DateTime(2027, 1, 1, 0, 0, 1);
      expect(naming.today(), '2027-01-01');
    });
  });

  group('KeyValueGalleryCounterStore', () {
    late InMemoryKeyValueStore values;
    late KeyValueGalleryCounterStore counter;

    setUp(() {
      values = InMemoryKeyValueStore();
      counter = KeyValueGalleryCounterStore(values);
    });

    test('starts at 1 on an empty store', () {
      expect(counter.nextNumber('2026-10-21'), 1);
    });

    test('asking does not use the number up', () {
      expect(counter.nextNumber('2026-10-21'), 1);
      expect(counter.nextNumber('2026-10-21'), 1);
    });

    test('continues after the last used number of the same day', () async {
      await counter.markUsed('2026-10-21', 1);
      expect(counter.nextNumber('2026-10-21'), 2);

      await counter.markUsed('2026-10-21', 2);
      expect(counter.nextNumber('2026-10-21'), 3);
    });

    test('starts again at 1 when the date changes', () async {
      await counter.markUsed('2026-10-21', 7);

      expect(counter.nextNumber('2026-10-22'), 1);
    });

    test('survives a restart: a new instance reads the same store', () async {
      await counter.markUsed('2026-10-21', 4);

      final reopened = KeyValueGalleryCounterStore(values);
      expect(reopened.nextNumber('2026-10-21'), 5);
    });

    test('a store with a missing number falls back to 1', () async {
      await values.setString(KeyValueGalleryCounterStore.keyDate, '2026-10-21');

      expect(counter.nextNumber('2026-10-21'), 1);
    });
  });
}
