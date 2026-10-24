import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/ocr_line.dart';
import 'package:one_click_scan/domain/ocr/confidence_filter.dart';
import 'package:one_click_scan/domain/ocr/image_decode_policy.dart';
import 'package:one_click_scan/domain/ocr/ocr_cancellation.dart';
import 'package:one_click_scan/domain/ocr/ocr_config.dart';

import '../../support/ocr_fakes.dart';

void main() {
  group('planImageDecode (the 8 MP and 400 MP limits)', () {
    test('small photos are decoded by Dart in a background isolate', () {
      expect(planImageDecode(0.1), ImageDecodePlan.dartIsolate);
      expect(planImageDecode(8.0), ImageDecodePlan.dartIsolate);
    });

    test('above 8 MP the decode is native', () {
      expect(planImageDecode(8.01), ImageDecodePlan.native);
      expect(planImageDecode(12.5), ImageDecodePlan.native);
    });

    test('above 50 MP it is still native (sampled), never a full decode', () {
      for (final mp in [50.0, 50.01, 200.0, 400.0]) {
        expect(planImageDecode(mp), ImageDecodePlan.native, reason: '$mp MP');
      }
    });

    test('above 400 MP the image is refused', () {
      expect(planImageDecode(400.01), ImageDecodePlan.tooLarge);
      expect(planImageDecode(4000), ImageDecodePlan.tooLarge);
    });

    test('the limits are the documented constants', () {
      expect(OcrConfig.dartDecodeMaxMegapixels, 8.0);
      expect(OcrConfig.fullDecodeMaxMegapixels, 50.0);
      expect(OcrConfig.maxMegapixels, 400.0);
      expect(OcrConfig.workingSide, 2560);
      expect(OcrConfig.threads, 4);
    });
  });

  group('OcrConfig', () {
    test('values decided from the phone measurements', () {
      expect(OcrConfig.detectionSide, 960);
      expect(OcrConfig.recognitionBatch, 1);
      expect(OcrConfig.pageTimeout, const Duration(seconds: 45));
      expect(OcrConfig.minLineConfidence, 0.65);
      expect(OcrConfig.borderlineConfidence, 0.5);
    });
  });

  group('applyConfidenceFilter', () {
    final raw = fakeResult([
      fakeLine('clear', confidence: 0.97, row: 0),
      fakeLine('border', confidence: OcrConfig.minLineConfidence, row: 1),
      fakeLine('scribble', confidence: 0.2, row: 2),
      fakeLine('doubtful', confidence: 0.55, row: 3),
    ]);

    test('flags only lines below the threshold and keeps every line', () {
      final filtered = applyConfidenceFilter(raw);

      expect(filtered.lines, hasLength(4));
      expect(filtered.lines.map((l) => l.filtered), [false, false, true, true]);
      expect(filtered.filteredCount, 2);
      expect(filtered.boxCount, 4);
    });

    test('never changes the text, even of filtered lines', () {
      final filtered = applyConfidenceFilter(raw);

      expect(filtered.lines.map((l) => l.text), [
        'clear',
        'border',
        'scribble',
        'doubtful',
      ]);
      expect(filtered.rawText, 'clear\nborder\nscribble\ndoubtful');
    });

    test('the visible text leaves out the filtered lines only', () {
      final filtered = applyConfidenceFilter(raw);

      expect(filtered.text, 'clear\nborder');
      expect(filtered.visibleLines, hasLength(2));
    });

    test('borderline lines (0.50 to 0.65) are counted', () {
      expect(raw.borderlineCount, 1); // 0.55; 0.65 itself is not below
      expect(
        fakeResult([
          fakeLine('a', confidence: 0.5),
          fakeLine('b', confidence: 0.649),
          fakeLine('c', confidence: 0.499),
          fakeLine('d', confidence: 0.65),
        ]).borderlineCount,
        2,
      );
    });

    test('the threshold is 0.65: a 0.60 line is flagged', () {
      final result = applyConfidenceFilter(
        fakeResult([fakeLine('x', confidence: 0.60)]),
      );
      expect(result.lines.single.filtered, isTrue);
    });

    test('a custom threshold is honoured', () {
      expect(applyConfidenceFilter(raw, threshold: 0.99).filteredCount, 4);
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
