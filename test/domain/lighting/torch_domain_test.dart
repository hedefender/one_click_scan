import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/scan_flow_mode.dart';
import 'package:one_click_scan/domain/entities/scan_mode.dart';
import 'package:one_click_scan/domain/lighting/light_metric.dart';
import 'package:one_click_scan/domain/lighting/lighting_config.dart';
import 'package:one_click_scan/domain/lighting/low_light_debouncer.dart';
import 'package:one_click_scan/domain/lighting/low_light_policy.dart';

/// Phase 6.2.1 (ADR-031): the second light threshold, the torch constants and
/// the flicker guard that keeps its mark across a torch change.
void main() {
  LightMetric paper(double p) => LightMetric(paper: p, contrast: 50);

  group('constants', () {
    test('the warning threshold is unchanged and the second one is equal', () {
      expect(LightingConfig.minPaperLevel, 40);
      expect(LightingConfig.enhancementHelpsMinPaperLevel, 40);
    });

    test('torch timing lives in the config', () {
      expect(LightingConfig.torchIdleTimeout, const Duration(seconds: 120));
      expect(
        LightingConfig.torchSettleDelay,
        const Duration(milliseconds: 500),
      );
    });
  });

  group('the second threshold changes the words only', () {
    test('below it: retake first; at or above it: the usual text', () {
      expect(LowLightPolicy.retakeFirst(paper(25), helpsMin: 30), isTrue);
      expect(LowLightPolicy.retakeFirst(paper(30), helpsMin: 30), isFalse);
      expect(LowLightPolicy.retakeFirst(paper(55), helpsMin: 30), isFalse);
    });

    test('a shot that was not measured is never "too dark"', () {
      expect(LowLightPolicy.retakeFirst(null), isFalse);
    });

    test(
      'a zone between the two (min 70, helps 40) when they are set apart',
      () {
        // The calibrated values may be 70 and 40: the config constants stay at
        // 40 and 40 now, so the zone is tested with injected values.
        expect(LowLightPolicy.retakeFirst(paper(55), helpsMin: 40), isFalse);
        expect(LowLightPolicy.retakeFirst(paper(35), helpsMin: 40), isTrue);
      },
    );

    test('with today\'s values every dark shot is also "too dark"', () {
      // Equal thresholds: the zone "dark but correctable" is empty.
      expect(LightingConfig.isLowLight(paper(39)), isTrue);
      expect(LowLightPolicy.retakeFirst(paper(39)), isTrue);
      expect(LightingConfig.isLowLight(paper(41)), isFalse);
      expect(LowLightPolicy.retakeFirst(paper(41)), isFalse);
    });

    test('the warning itself is still decided by minPaperLevel only', () {
      expect(
        LowLightPolicy.onCapture(
          metric: paper(39),
          mode: ScanMode.single,
          flow: ScanFlowMode.oneClick,
        ),
        LowLightAction.askNow,
      );
    });
  });

  group('debouncer keeps the mark when the torch changes', () {
    test('restart forgets the last sample but not the mark', () {
      final d = LowLightDebouncer();
      d
        ..add(paper(10))
        ..add(paper(10));
      expect(d.isLow, isTrue);

      d.restart();
      expect(d.isLow, isTrue, reason: 'no fresh sample yet');
      expect(d.add(paper(90)), isTrue, reason: 'one sample is not enough');
      expect(d.add(paper(90)), isFalse);
    });

    test('reset still clears everything', () {
      final d = LowLightDebouncer()
        ..add(paper(10))
        ..add(paper(10))
        ..reset();
      expect(d.isLow, isFalse);
    });
  });
}
