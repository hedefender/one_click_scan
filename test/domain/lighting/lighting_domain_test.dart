import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/data/datasources/key_value_flash_preference_store.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';
import 'package:one_click_scan/domain/entities/scan_flow_mode.dart';
import 'package:one_click_scan/domain/entities/scan_mode.dart';
import 'package:one_click_scan/domain/lighting/enhancement_gate.dart';
import 'package:one_click_scan/domain/lighting/flash_mode.dart';
import 'package:one_click_scan/domain/lighting/light_metric.dart';
import 'package:one_click_scan/domain/lighting/lighting_config.dart';
import 'package:one_click_scan/domain/lighting/low_light_debouncer.dart';
import 'package:one_click_scan/domain/lighting/low_light_policy.dart';

import '../../support/fakes.dart';
import '../../support/ocr_fakes.dart';

/// A synthetic page: [paper] level with a few ink pixels at [ink].
LightMetric metricOf({required int paper, required int ink, int size = 100}) {
  final y = Uint8List(size * size)..fillRange(0, size * size, paper);
  // 10% of the pixels are ink (text), the rest is paper.
  for (var i = 0; i < size * size ~/ 10; i++) {
    y[i * 10] = ink;
  }
  return LightMetric.fromLuma(y, width: size, height: size)!;
}

void main() {
  group('LightMetric', () {
    test('a bright page has a high paper level and a high contrast', () {
      final m = metricOf(paper: 235, ink: 30);
      expect(m.paper, closeTo(92, 1));
      expect(m.contrast, greaterThan(60));
      expect(LightingConfig.isLowLight(m), isFalse);
    });

    test('a dark shot of the same page is low light', () {
      final m = metricOf(paper: 70, ink: 10);
      expect(m.paper, closeTo(27, 1));
      expect(LightingConfig.isLowLight(m), isTrue);
    });

    test('a faint thermal receipt is bright but has a low contrast', () {
      // Faded ink: the paper is well lit, so no warning (more light would not
      // give the ink back); the contrast number shows it on the diagnostics.
      final m = metricOf(paper: 230, ink: 190);
      expect(LightingConfig.isLowLight(m), isFalse);
      expect(m.contrast, lessThan(LightingConfig.faintContrast + 5));
    });

    test('the paper level does not depend on how much text there is', () {
      final empty = LightMetric.fromLuma(
        Uint8List(1000)..fillRange(0, 1000, 200),
        width: 100,
        height: 10,
      )!;
      final texty = metricOf(paper: 200, ink: 20);
      expect(texty.paper, closeTo(empty.paper, 1));
    });

    test('rows may be padded and pixels skipped', () {
      // 10x10 picture in a plane with a row stride of 16.
      final plane = Uint8List(16 * 10)..fillRange(0, 160, 128);
      final m = LightMetric.fromLuma(
        plane,
        width: 10,
        height: 10,
        rowStride: 16,
        stride: 3,
      )!;
      expect(m.paper, closeTo(50, 1));
    });

    test('nothing to read gives null', () {
      expect(LightMetric.fromLuma(Uint8List(0), width: 0, height: 0), isNull);
    });

    test('the threshold is applied in one place', () {
      const below = LightMetric(paper: 39.9, contrast: 50);
      const above = LightMetric(paper: 40, contrast: 50);
      expect(LightingConfig.isLowLight(below), isTrue);
      expect(LightingConfig.isLowLight(above), isFalse);
      expect(LightingConfig.minPaperLevel, inInclusiveRange(30, 50));
    });
  });

  group('FlashMode storage', () {
    test('Off and Auto are remembered, On is stored as Auto', () {
      expect(FlashMode.off.storedName, 'off');
      expect(FlashMode.auto.storedName, 'auto');
      expect(FlashMode.on.storedName, 'auto');
    });

    test('loading: missing is Off, a stored on becomes Auto', () {
      expect(FlashMode.fromStored(null), FlashMode.off);
      expect(FlashMode.fromStored('nonsense'), FlashMode.off);
      expect(FlashMode.fromStored('auto'), FlashMode.auto);
      expect(FlashMode.fromStored('on'), FlashMode.auto);
    });

    test('the button goes Off, Auto, On, Off', () {
      expect(FlashMode.off.next, FlashMode.auto);
      expect(FlashMode.auto.next, FlashMode.on);
      expect(FlashMode.on.next, FlashMode.off);
    });

    test('the store: On is saved, the next start loads Auto', () async {
      final kv = InMemoryKeyValueStore();
      final store = KeyValueFlashPreferenceStore(kv);
      expect(store.load(), FlashMode.off);
      await store.save(FlashMode.on);
      expect(kv.getString(KeyValueFlashPreferenceStore.keyMode), 'auto');
      expect(KeyValueFlashPreferenceStore(kv).load(), FlashMode.auto);
      await store.save(FlashMode.off);
      expect(KeyValueFlashPreferenceStore(kv).load(), FlashMode.off);
    });
  });

  group('LowLightPolicy', () {
    const dark = LightMetric(paper: 20, contrast: 20);
    const bright = LightMetric(paper: 90, contrast: 60);

    LowLightAction decide(LightMetric? m, ScanMode mode, ScanFlowMode flow) =>
        LowLightPolicy.onCapture(metric: m, mode: mode, flow: flow);

    test('a bright or unmeasured shot is never a question', () {
      for (final mode in ScanMode.values) {
        for (final flow in ScanFlowMode.values) {
          expect(decide(bright, mode, flow), LowLightAction.none);
          expect(decide(null, mode, flow), LowLightAction.none);
        }
      }
    });

    test('One Click, Single: the flow stops with the dialog', () {
      expect(
        decide(dark, ScanMode.single, ScanFlowMode.oneClick),
        LowLightAction.askNow,
      );
    });

    test('One Click, Multi: a mark, the rhythm of the shots is not broken', () {
      expect(
        decide(dark, ScanMode.multi, ScanFlowMode.oneClick),
        LowLightAction.markPage,
      );
    });

    test('preview: no interruption, the banner comes later', () {
      expect(
        decide(dark, ScanMode.single, ScanFlowMode.preview),
        LowLightAction.bannerLater,
      );
      expect(
        decide(dark, ScanMode.multi, ScanFlowMode.preview),
        LowLightAction.bannerLater,
      );
    });

    test('the summary before the send: only in One Click, only if flagged', () {
      expect(
        LowLightPolicy.needsSummary(
          flow: ScanFlowMode.oneClick,
          undecidedDarkPages: 1,
        ),
        isTrue,
      );
      expect(
        LowLightPolicy.needsSummary(
          flow: ScanFlowMode.oneClick,
          undecidedDarkPages: 0,
        ),
        isFalse,
      );
      expect(
        LowLightPolicy.needsSummary(
          flow: ScanFlowMode.preview,
          undecidedDarkPages: 3,
        ),
        isFalse,
      );
    });
  });

  group('LowLightDebouncer', () {
    const dark = LightMetric(paper: 20, contrast: 20);
    const bright = LightMetric(paper: 90, contrast: 60);

    test('changes only after two samples in a row agree', () {
      final d = LowLightDebouncer();
      expect(d.add(dark), isFalse);
      expect(d.add(dark), isTrue);
      expect(d.add(bright), isTrue);
      expect(d.add(dark), isTrue);
      expect(d.add(bright), isTrue);
      expect(d.add(bright), isFalse);
    });
  });

  group('safety valve of the light correction', () {
    OcrOutcome reading(int words) =>
        OcrSuccess(fakeResult([fakeLine(List.filled(words, 'w').join(' '))]));

    test('words are counted on the visible lines', () {
      expect(countWords(reading(7)), 7);
      expect(countWords(const OcrCancelled()), 0);
      expect(countWords(null), 0);
    });

    test('more words after the correction: the corrected one', () {
      expect(
        chooseByWords(originalWords: 10, enhancedWords: 11),
        EnhancementChoice.enhanced,
      );
    });

    test('fewer words: the original (letters were lost)', () {
      expect(
        chooseByWords(originalWords: 10, enhancedWords: 8),
        EnhancementChoice.original,
      );
    });

    test('a tie goes to the original', () {
      expect(
        chooseByWords(originalWords: 10, enhancedWords: 10),
        EnhancementChoice.original,
      );
    });
  });
}
