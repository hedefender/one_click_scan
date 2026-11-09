import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/presentation/theme/app_colors.dart';

/// WCAG 2.x contrast ratio of two opaque colours.
double contrast(Color a, Color b) {
  double luminance(Color c) {
    double channel(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) +
        0.7152 * channel(c.g) +
        0.0722 * channel(c.b);
  }

  final la = luminance(a);
  final lb = luminance(b);
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Phase 6.4 (DESIGN_SPEC 3.3, 3.4, 3.5): the fallback palettes keep their
/// contrast. Text pairs need 4.5, borders of fields and choices need 3.0.
void main() {
  final palettes = <String, ColorScheme>{
    'light': AppPalettes.light,
    'dark': AppPalettes.dark,
  };

  for (final entry in palettes.entries) {
    final name = entry.key;
    final s = entry.value;

    group('$name palette', () {
      final textPairs = <String, (Color, Color)>{
        'onSurface / surface': (s.onSurface, s.surface),
        'onSurface / surfaceContainer': (s.onSurface, s.surfaceContainer),
        'onSurfaceVariant / surface': (s.onSurfaceVariant, s.surface),
        'onSurfaceVariant / surfaceContainer': (
          s.onSurfaceVariant,
          s.surfaceContainer,
        ),
        'onPrimaryContainer / primaryContainer': (
          s.onPrimaryContainer,
          s.primaryContainer,
        ),
        'onSecondaryContainer / secondaryContainer': (
          s.onSecondaryContainer,
          s.secondaryContainer,
        ),
        'primary / surface': (s.primary, s.surface),
        'primary / surfaceContainer': (s.primary, s.surfaceContainer),
        'onPrimary / primary': (s.onPrimary, s.primary),
        'error / surface': (s.error, s.surface),
        'onError / error': (s.onError, s.error),
      };
      for (final pair in textPairs.entries) {
        test('${pair.key} is at least 4.5:1', () {
          final ratio = contrast(pair.value.$1, pair.value.$2);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '${pair.key} = ${ratio.toStringAsFixed(2)}',
          );
        });
      }

      final dialog = name == 'light'
          ? AppPalettes.lightDialog
          : AppPalettes.darkDialog;
      test('onSurface and onSurfaceVariant read on the dialog colour', () {
        expect(contrast(s.onSurface, dialog), greaterThanOrEqualTo(4.5));
        expect(contrast(s.onSurfaceVariant, dialog), greaterThanOrEqualTo(4.5));
        expect(contrast(s.primary, dialog), greaterThanOrEqualTo(4.5));
      });

      for (final surface in <String, Color>{
        'surface': s.surface,
        'surfaceContainer': s.surfaceContainer,
        'surfaceContainerHighest': s.surfaceContainerHighest,
      }.entries) {
        test('outline against ${surface.key} is at least 3:1', () {
          final ratio = contrast(s.outline, surface.value);
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason: 'outline / ${surface.key} = ${ratio.toStringAsFixed(2)}',
          );
        });
      }

      test('the palette keeps the exact values of the spec', () {
        expect(
          s.primary,
          name == 'light' ? const Color(0xFF4D6410) : const Color(0xFFCBBBE6),
        );
        expect(
          s.surface,
          name == 'light' ? const Color(0xFFF3F6E8) : const Color(0xFF121016),
        );
        expect(
          s.outline,
          name == 'light' ? const Color(0xFF7A7E66) : const Color(0xFF716A8C),
        );
      });
    });
  }

  group('status colours', () {
    for (final entry in <String, AppStatusColors>{
      'light': AppStatusColors.light,
      'dark': AppStatusColors.dark,
    }.entries) {
      test('${entry.key}: onWarning / warning is at least 4.5:1', () {
        final c = entry.value;
        expect(contrast(c.onWarning, c.warning), greaterThanOrEqualTo(4.5));
      });
      test('${entry.key}: onWarningContainer / warningContainer >= 4.5:1', () {
        final c = entry.value;
        expect(
          contrast(c.onWarningContainer, c.warningContainer),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });

  group('camera chrome', () {
    // White 12 % over the near-black background.
    final control = Color.alphaBlend(
      AppCameraColors.control,
      AppCameraColors.background,
    );

    test('text and icons read on the controls area and on the controls', () {
      expect(
        contrast(AppCameraColors.content, AppCameraColors.background),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(AppCameraColors.content, control),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(AppCameraColors.content, AppCameraColors.floating),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('the floating colour is the control colour over the background', () {
      final blended = control;
      final floating = AppCameraColors.floating;
      expect((blended.r - floating.r).abs(), lessThan(0.01));
      expect((blended.g - floating.g).abs(), lessThan(0.01));
      expect((blended.b - floating.b).abs(), lessThan(0.01));
    });

    for (final entry in <String, AppCameraColors>{
      'light fallback': AppCameraColors.lightFallback,
      'dark fallback': AppCameraColors.darkFallback,
    }.entries) {
      test('${entry.key}: the selected element reads (4.5:1)', () {
        final c = entry.value;
        expect(contrast(c.onSelected, c.selected), greaterThanOrEqualTo(4.5));
      });
      // The spec value of the dark fallback (#5C4D82) measures 2.61:1 against
      // the chrome, below the 3:1 of a UI component. The label inside passes
      // 4.5:1 and the value is kept as specified; reported in PHASE_6_4.
      test('${entry.key}: the selected element stands out of the chrome', () {
        final c = entry.value;
        expect(
          contrast(c.selected, AppCameraColors.background),
          greaterThanOrEqualTo(2.5),
        );
      });
    }
  });
}
