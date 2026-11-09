import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/core/config/app_config.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/first_run/first_run_keys.dart';
import 'package:one_click_scan/features/help/help_keys.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/scan/scan_keys.dart';
import 'package:one_click_scan/features/settings/settings_keys.dart';

import '../../support/fakes.dart';
import '../../support/mail_fakes.dart';
import '../../support/ocr_fakes.dart';
import '../../support/pdf_fakes.dart';
import '../../support/scan_fakes.dart';

/// Phase 6.4: the main screens at 360 x 640 dp, in Greek, with the system text
/// at 1.0 and 1.3, in the light and the dark theme: no overflow. Noto Sans is
/// wider than Roboto, so this is the test that would show it.
void main() {
  Future<void> useSmallPhone(WidgetTester tester, double textScale) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3; // 360 x 640 dp
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
  }

  Future<void> setBrightness(WidgetTester tester, Brightness value) async {
    tester.platformDispatcher.platformBrightnessTestValue = value;
  }

  /// Scrolls the first scrollable of the screen step by step to its end and
  /// fails on any layout exception on the way.
  Future<void> scrollThrough(WidgetTester tester, String what) async {
    expect(tester.takeException(), isNull, reason: '$what: first frame');
    final scrollable = find.byType(Scrollable);
    if (scrollable.evaluate().isEmpty) return;
    for (var i = 0; i < 40; i++) {
      await tester.drag(scrollable.first, const Offset(0, -240));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$what: scroll step $i');
    }
  }

  Future<GetIt> pumpApp(
    WidgetTester tester, {
    bool wizardDone = true,
    OcrTestRig? ocr,
    PdfTestRig? pdf,
    MailTestRig? mail,
    FakeScanFileStore? store,
  }) async {
    final values = InMemoryKeyValueStore();
    Future<GetIt> build() => buildTestContainer(
      config: AppConfig.forDeviceLanguage('el'),
      store: values,
      scanFileStore: store,
      ocr: ocr?.services,
      pdf: pdf?.services,
      mail: mail?.services,
    );
    if (wizardDone) {
      final seed = await build();
      await seed<SettingsRepository>().save(
        (await seed<SettingsRepository>().load()).copyWith(
          firstRunCompleted: true,
          storageFolder: testFolder,
          mailProvider: MailProviderId.gmail,
          senderAccount: testAccount,
        ),
      );
    }
    final container = await build();
    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();
    return container;
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 1.3]) {
      final label = '${brightness.name}, text x$scale';

      testWidgets('wizard, all steps ($label)', (tester) async {
        await useSmallPhone(tester, scale);
        await setBrightness(tester, brightness);
        await pumpApp(tester, wizardDone: false);
        await scrollThrough(tester, 'wizard language step');
        for (var step = 0; step < 6; step++) {
          if (find.byKey(FirstRunKeys.pickFolder).evaluate().isNotEmpty) {
            await tester.ensureVisible(find.byKey(FirstRunKeys.pickFolder));
            await tester.tap(find.byKey(FirstRunKeys.pickFolder));
            await tester.pumpAndSettle();
          }
          if (find.byKey(FirstRunKeys.sender).evaluate().isNotEmpty) {
            await tester.tap(find.text('Gmail'));
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byKey(FirstRunKeys.sender),
              'sender@example.com',
            );
            await tester.pumpAndSettle();
          }
          if (find.byKey(FirstRunKeys.flowPreview).evaluate().isNotEmpty) {
            await tester.ensureVisible(find.byKey(FirstRunKeys.flowPreview));
            await tester.tap(find.byKey(FirstRunKeys.flowPreview));
            await tester.pumpAndSettle();
          }
          await scrollThrough(tester, 'wizard step $step');
          if (find.byKey(FirstRunKeys.next).evaluate().isEmpty) break;
          await tester.ensureVisible(find.byKey(FirstRunKeys.next));
          await tester.tap(find.byKey(FirstRunKeys.next));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('home, settings and Help ($label)', (tester) async {
        await useSmallPhone(tester, scale);
        await setBrightness(tester, brightness);
        await pumpApp(tester);
        await scrollThrough(tester, 'home');

        await tester.tap(find.byKey(HomeKeys.settings));
        await tester.pumpAndSettle();
        await scrollThrough(tester, 'settings');

        // scrollThrough left the list at its end: come back up to the entry.
        await tester.scrollUntilVisible(
          find.byKey(SettingsKeys.helpEntry),
          -300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(SettingsKeys.helpEntry));
        await tester.pumpAndSettle();
        expect(find.byKey(HelpKeys.page), findsOneWidget);
        await scrollThrough(tester, 'help');
      });

      testWidgets('scan and the result screen ($label)', (tester) async {
        await useSmallPhone(tester, scale);
        await setBrightness(tester, brightness);
        final mail = MailTestRig()
          ..storePassword(provider: MailProviderId.gmail);
        await pumpApp(
          tester,
          ocr: OcrTestRig(),
          pdf: PdfTestRig(),
          mail: mail,
          store: FakeScanFileStore(),
        );
        await tester.tap(find.byKey(HomeKeys.scanAndSend));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'camera screen');
        await tester.tap(find.byKey(ScanKeys.capture));
        await tester.pumpAndSettle();
        await scrollThrough(tester, 'result');
      });
    }
  }
}
