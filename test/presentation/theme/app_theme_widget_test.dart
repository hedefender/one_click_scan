import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/presentation/theme/app_colors.dart';
import 'package:one_click_scan/presentation/theme/app_theme.dart';

/// Phase 6.4: the basic elements build with the light, the dark and a
/// "dynamic" (system colours) scheme, follow the spec, and the warning stays
/// amber in all three.
void main() {
  // A scheme that stands for the system colours (another seed).
  final fakeLight = ColorScheme.fromSeed(seedColor: Colors.teal);
  final fakeDark = ColorScheme.fromSeed(
    seedColor: Colors.teal,
    brightness: Brightness.dark,
  );

  final themes = <String, ThemeData>{
    'light': AppTheme.light(),
    'dark': AppTheme.dark(),
    'dynamic light': AppTheme.light(
      systemLight: fakeLight,
      systemDark: fakeDark,
    ),
    'dynamic dark': AppTheme.dark(systemLight: fakeLight, systemDark: fakeDark),
  };

  Widget host(ThemeData theme, Widget child) => MaterialApp(
    theme: theme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  for (final entry in themes.entries) {
    final name = entry.key;
    final theme = entry.value;

    group(name, () {
      testWidgets('the basic elements build and follow the roles', (
        tester,
      ) async {
        final scheme = theme.colorScheme;
        await tester.pumpWidget(
          host(
            theme,
            Column(
              children: [
                FilledButton(onPressed: () {}, child: const Text('filled')),
                Builder(
                  builder: (context) => FilledButton.tonal(
                    onPressed: () {},
                    style: AppButtonStyles.tonal(context),
                    child: const Text('tonal'),
                  ),
                ),
                OutlinedButton(onPressed: () {}, child: const Text('outlined')),
                TextButton(onPressed: () {}, child: const Text('text')),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('one')),
                    ButtonSegment(value: 2, label: Text('two')),
                  ],
                  selected: const {1},
                  onSelectionChanged: (_) {},
                ),
                const TextField(
                  decoration: InputDecoration(labelText: 'field'),
                ),
                const Card(child: Text('card')),
              ],
            ),
          ),
        );
        expect(tester.takeException(), isNull);

        Material materialOf(String label) => tester.widget<Material>(
          find
              .ancestor(of: find.text(label), matching: find.byType(Material))
              .first,
        );

        // Filled button: the container colours, stadium, 56 high.
        final filled = materialOf('filled');
        expect(filled.color, scheme.primaryContainer);
        expect(filled.shape, isA<StadiumBorder>());
        expect(
          tester.getSize(find.widgetWithText(FilledButton, 'filled')).height,
          56,
        );
        // Tonal button.
        expect(materialOf('tonal').color, scheme.secondaryContainer);
        // Outlined button: the outline colour, text in primary.
        final outlined = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'outlined'),
        );
        final outlineStyle = outlined.style ?? const ButtonStyle();
        expect(outlineStyle, isNotNull);
        final outlinedMaterial = materialOf('outlined');
        expect(outlinedMaterial.shape, isA<StadiumBorder>());
        expect(
          (outlinedMaterial.shape as StadiumBorder).side.color,
          scheme.outline,
        );
        // Card: radius 24, a 1 px outline only in the dark theme.
        final card = tester.widget<Card>(find.byType(Card));
        final shape = card.shape ?? theme.cardTheme.shape;
        expect(shape, isA<RoundedRectangleBorder>());
        final cardShape = shape! as RoundedRectangleBorder;
        expect(cardShape.borderRadius, BorderRadius.circular(24));
        if (theme.brightness == Brightness.dark) {
          expect(cardShape.side.color, scheme.outlineVariant);
          expect(cardShape.side.width, 1);
        } else {
          expect(cardShape.side, BorderSide.none);
        }
        // Elevation 0 everywhere.
        expect(theme.cardTheme.elevation, 0);
        expect(theme.dialogTheme.elevation, 0);
      });

      testWidgets('a dialog is radius 28 on the dialog colour', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('title'),
                      content: const Text('body'),
                      actions: [
                        TextButton(onPressed: () {}, child: const Text('ok')),
                      ],
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final dialog = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(Material),
              )
              .first,
        );
        final dynamicColors = name.startsWith('dynamic');
        final expected = dynamicColors
            ? theme.colorScheme.surfaceContainerHigh
            : (theme.brightness == Brightness.dark
                  ? AppPalettes.darkDialog
                  : AppPalettes.lightDialog);
        expect(dialog.color, expected);
        expect(
          (dialog.shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(28),
        );
      });

      test('the warning stays amber, whatever the colour source', () {
        final status = theme.extension<AppStatusColors>()!;
        final expected = theme.brightness == Brightness.dark
            ? AppStatusColors.dark
            : AppStatusColors.light;
        expect(status.warning, expected.warning);
        expect(status.warningContainer, expected.warningContainer);
        // Amber: hue between 35 and 50 degrees, in light and dark.
        for (final c in [status.warning, status.warningContainer]) {
          final hue = HSLColor.fromColor(c).hue;
          expect(hue, inInclusiveRange(35, 50));
        }
      });

      test('the type scale is Noto Sans with the sizes of the spec', () {
        final t = theme.textTheme;
        expect(t.headlineSmall!.fontSize, 26);
        expect(t.headlineSmall!.fontWeight, FontWeight.w600);
        expect(t.titleLarge!.fontSize, 22);
        expect(t.titleLarge!.fontWeight, FontWeight.w500);
        expect(t.titleMedium!.fontSize, 18);
        expect(t.bodyLarge!.fontSize, 16);
        expect(t.bodyMedium!.fontSize, 15);
        expect(t.bodySmall!.fontSize, 13);
        expect(t.labelLarge!.fontSize, 15);
        expect(t.labelLarge!.fontWeight, FontWeight.w600);
        expect(t.bodyMedium!.fontFamily, 'NotoSans');
      });
    });
  }

  test('the colour source is reported for the diagnostics', () {
    expect(AppTheme.light().extension<AppColorSource>()!.system, isFalse);
    expect(
      AppTheme.dark(systemDark: fakeDark).extension<AppColorSource>()!.system,
      isTrue,
    );
  });

  test('the camera chrome selected colour of each source (spec 3.5)', () {
    expect(
      AppTheme.light().extension<AppCameraColors>()!.selected,
      const Color(0xFFD7EF6C),
    );
    expect(
      AppTheme.dark().extension<AppCameraColors>()!.selected,
      const Color(0xFF5C4D82),
    );
    // With system colours: the container colours of the dark scheme, also
    // inside the light theme.
    final system = AppTheme.light(systemLight: fakeLight, systemDark: fakeDark);
    expect(
      system.extension<AppCameraColors>()!.selected,
      fakeDark.primaryContainer,
    );
    expect(
      system.extension<AppCameraColors>()!.onSelected,
      fakeDark.onPrimaryContainer,
    );
  });

  test('the font comes from assets: three weights and no network package', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: NotoSans'));
    for (final w in ['Regular', 'Medium', 'SemiBold']) {
      expect(pubspec, contains('assets/fonts/NotoSans-$w.ttf'));
      expect(File('assets/fonts/NotoSans-$w.ttf').existsSync(), isTrue);
    }
    expect(pubspec, isNot(contains('google_fonts')));
    // No code of the app fetches a font (or anything) for the theme.
    for (final file in Directory('lib/presentation/theme').listSync()) {
      if (file is! File) continue;
      final source = file.readAsStringSync();
      expect(source, isNot(contains('google_fonts')));
      expect(source, isNot(contains('dart:io')));
      expect(source, isNot(contains('http')));
    }
  });
}
