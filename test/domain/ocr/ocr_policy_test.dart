import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/ocr_line.dart';
import 'package:one_click_scan/domain/ocr/confidence_filter.dart';
import 'package:one_click_scan/domain/ocr/image_decode_policy.dart';
import 'package:one_click_scan/domain/ocr/ocr_cancellation.dart';
import 'package:one_click_scan/domain/ocr/ocr_config.dart';

import '../../support/ocr_fakes.dart';

void main() {
  group('planImageDecode (the 8 and 50 MP limits)', () {
    test('small photos are decoded by Dart in a background isolate', () {
      expect(planImageDecode(0.1), ImageDecodePlan.dartIsolate);
      expect(planImageDecode(8.0), ImageDecodePlan.dartIsolate);
    });

    test('above 8 MP the decode is native', () {
      expect(planImageDecode(8.01), ImageDecodePlan.native);
      expect(planImageDecode(12), ImageDecodePlan.native);
      expect(planImageDecode(50.0), ImageDecodePlan.native);
    });

    test('above 50 MP the image is refused', () {
      expect(planImageDecode(50.01), ImageDecodePlan.tooLarge);
      expect(planImageDecode(200), ImageDecodePlan.tooLarge);
    });

    test('the limits are the documented constants', () {
      expect(OcrConfig.dartDecodeMaxMegapixels, 8.0);
      expect(OcrConfig.maxMegapixels, 50.0);
      expect(OcrConfig.workingSide, 2560);
    });
  });

  group('OcrConfig', () {
    test('values decided from the phone measurements', () {
      expect(OcrConfig.detectionSide, 960);
      expect(OcrConfig.recognitionBatch, 1);
      expect(OcrConfig.pageTimeout, const Duration(seconds: 45));
      expect(OcrConfig.minLineConfidence, inInclusiveRange(0.3, 0.7));
    });
  });

  group('applyConfidenceFilter', () {
    final raw = fakeResult([
      fakeLine('clear', confidence: 0.97, row: 0),
      fakeLine('border', confidence: OcrConfig.minLineConfidence, row: 1),
      fakeLine('scribble', confidence: 0.2, row: 2),
    ]);

    test('flags only lines below the threshold and keeps every line', () {
      final filtered = applyConfidenceFilter(raw);

      expect(filtered.lines, hasLength(3));
      expect(filtered.lines.map((l) => l.filtered), [false, false, true]);
      expect(filtered.filteredCount, 1);
      expect(filtered.boxCount, 3);
    });

    test('never changes the text, even of filtered lines', () {
      final filtered = applyConfidenceFilter(raw);

      expect(filtered.lines.map((l) => l.text), [
        'clear',
        'border',
        'scribble',
      ]);
      expect(filtered.rawText, 'clear\nborder\nscribble');
    });

    test('the visible text leaves out the filtered lines only', () {
      final filtered = applyConfidenceFilter(raw);

      expect(filtered.text, 'clear\nborder');
      expect(filtered.visibleLines, hasLength(2));
    });

    test('a custom threshold is honoured', () {
      expect(applyConfidenceFilter(raw, threshold: 0.99).filteredCount, 3);
      expect(applyConfidenceFilter(raw, threshold: 0.0).filteredCount, 0);
    });
  });

  group('OcrResult text', () {
    test(
      'segments of one row are joined with a space, rows with a newline',
      () {
        final result = fakeResult([
          fakeLine('Total', row: 0),
          fakeLine('45,90', row: 0),
          fakeLine('Thank you', row: 1),
        ]);

        expect(result.text, 'Total 45,90\nThank you');
      },
    );

    test('an empty page has empty text', () {
      expect(fakeResult(const []).text, '');
    });
  });

  group('OcrLine', () {
    test('keeps charBoxes null in Phase 2', () {
      expect(fakeLine('x').charBoxes, isNull);
    });
  });

  group('OcrCancellation', () {
    test('cancel is idempotent and completes whenCancelled', () async {
      final c = OcrCancellation();
      expect(c.isCancelled, isFalse);
      c
        ..cancel()
        ..cancel();
      expect(c.isCancelled, isTrue);
      await c.whenCancelled;
    });
  });

  test('OcrPoint equality', () {
    expect(const OcrPoint(0.1, 0.2), const OcrPoint(0.1, 0.2));
  });
}
