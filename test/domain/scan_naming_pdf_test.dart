import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/scan/scan_naming.dart';

void main() {
  final naming = ScanNaming(() => DateTime(2026, 10, 21, 19, 5, 12));

  group('PDF names (ADR-005, ADR-015)', () {
    test('<stem>.pdf', () {
      expect(naming.pdfName('2026-10-21_19-05-12'), '2026-10-21_19-05-12.pdf');
      expect(
        naming.pdfName('2026-10-21_19-05-12-2'),
        '2026-10-21_19-05-12-2.pdf',
      );
    });

    test('the stem of a PDF is read back from its name', () {
      expect(
        naming.existingStems([
          '2026-10-21_19-05-12.pdf',
          '2026-10-21_19-05-12-2.pdf',
          '2026-10-21_19-05-12_1.jpg',
          'readme.txt',
        ]),
        {'2026-10-21_19-05-12', '2026-10-21_19-05-12-2'},
      );
    });

    test('a free stem stays as it is', () {
      expect(naming.availableStem('a', const {}), 'a');
      expect(naming.availableStem('a', const {'b'}), 'a');
    });

    test('a taken stem gets -2, then -3, and so on', () {
      expect(naming.availableStem('a', const {'a'}), 'a-2');
      expect(naming.availableStem('a', const {'a', 'a-2'}), 'a-3');
      expect(naming.availableStem('a', const {'a', 'a-2', 'a-3'}), 'a-4');
    });

    test('a gap is not filled twice over a taken stem', () {
      expect(naming.availableStem('a', const {'a', 'a-3'}), 'a-2');
    });
  });
}
