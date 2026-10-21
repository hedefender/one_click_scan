import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/scan/scan_naming.dart';

void main() {
  ScanNaming namingAt(DateTime time) => ScanNaming(() => time);

  test('stem is the device time as YYYY-MM-DD_HH-MM-SS', () {
    final naming = namingAt(DateTime(2026, 3, 7, 9, 5, 2));

    expect(naming.nextStem({}), '2026-03-07_09-05-02');
  });

  test('the injected clock is read on every call', () {
    var time = DateTime(2026, 10, 21, 19, 5, 12);
    final naming = ScanNaming(() => time);

    expect(naming.nextStem({}), '2026-10-21_19-05-12');
    time = DateTime(2026, 10, 21, 19, 5, 13);
    expect(naming.nextStem({}), '2026-10-21_19-05-13');
  });

  test('a taken stem gets -2, then -3', () {
    final naming = namingAt(DateTime(2026, 10, 21, 19, 5, 12));

    expect(naming.nextStem({'2026-10-21_19-05-12'}), '2026-10-21_19-05-12-2');
    expect(
      naming.nextStem({'2026-10-21_19-05-12', '2026-10-21_19-05-12-2'}),
      '2026-10-21_19-05-12-3',
    );
  });

  test('a free -2 slot is not skipped over a taken base only', () {
    final naming = namingAt(DateTime(2026, 10, 21, 19, 5, 12));

    // The base is free, so it is used even if a -2 exists.
    expect(naming.nextStem({'2026-10-21_19-05-12-2'}), '2026-10-21_19-05-12');
  });

  test('pictures are numbered from 1', () {
    final naming = namingAt(DateTime(2026, 10, 21, 19, 5, 12));

    expect(
      naming.pictureName('2026-10-21_19-05-12', 1),
      '2026-10-21_19-05-12_1.jpg',
    );
    expect(
      naming.pictureName('2026-10-21_19-05-12-2', 12),
      '2026-10-21_19-05-12-2_12.jpg',
    );
  });

  test('existing stems are read from picture and PDF names', () {
    final naming = namingAt(DateTime(2026, 10, 21, 19, 5, 12));

    expect(
      naming.existingStems([
        '2026-10-21_19-05-12_1.jpg',
        '2026-10-21_19-05-12_2.jpg',
        '2026-10-21_19-05-12-2_1.jpg',
        '2026-10-20_08-00-00.pdf',
        'notes.txt',
        'holiday.jpg',
      ]),
      {'2026-10-21_19-05-12', '2026-10-21_19-05-12-2', '2026-10-20_08-00-00'},
    );
  });

  test('two scans in the same second end up with different stems', () {
    final naming = namingAt(DateTime(2026, 10, 21, 19, 5, 12));
    final names = <String>[];

    for (var scan = 0; scan < 3; scan++) {
      final stem = naming.nextStem(naming.existingStems(names));
      names.add(naming.pictureName(stem, 1));
    }

    expect(names, [
      '2026-10-21_19-05-12_1.jpg',
      '2026-10-21_19-05-12-2_1.jpg',
      '2026-10-21_19-05-12-3_1.jpg',
    ]);
  });
}
