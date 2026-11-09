import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';
import 'package:one_click_scan/domain/entities/scan_flow_mode.dart';
import 'package:one_click_scan/domain/lighting/flash_mode.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/scan/focus_tap_layer.dart';
import 'package:one_click_scan/features/scan/scan_keys.dart';
import 'package:one_click_scan/presentation/theme/app_colors.dart';

import '../../support/fakes.dart';
import '../../support/mail_fakes.dart';
import '../../support/ocr_fakes.dart';
import '../../support/pdf_fakes.dart';
import '../../support/scan_fakes.dart';

/// Phase 6.2 screens: the flash button, tap-to-focus, the "low light" mark,
/// the dialog with three choices, the bar of Multi and the banner of the
/// preview.
void main() {
  late FakeCameraService camera;
  late FakeScanFileStore store;
  late FakeScanTempStore temp;
  late FakeLightMeter meter;
  late OcrTestRig rig;
  late FakeEnhancer enhancer;
  late PdfTestRig pdf;
  late MailTestRig mail;

  Future<void> pumpScan(
    WidgetTester tester, {
    bool flash = true,
    ScanFlowMode flow = ScanFlowMode.oneClick,
  }) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    camera = FakeCameraService(flashAvailable: flash);
    store = FakeScanFileStore();
    temp = FakeScanTempStore();
    meter = FakeLightMeter();
    enhancer = FakeEnhancer();
    rig = OcrTestRig(enhancer: enhancer);
    pdf = PdfTestRig();
    mail = MailTestRig()..storePassword();
    final kv = InMemoryKeyValueStore();
    Future<GetIt> build() => buildTestContainer(
      store: kv,
      camera: camera,
      scanFileStore: store,
      scanTempStore: temp,
      ocr: rig.services,
      lightMeter: meter,
      pdf: pdf.services,
      mail: mail.services,
    );
    final seed = await build();
    await seed<SettingsRepository>().save(
      (await seed<SettingsRepository>().load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        mailProvider: MailProviderId.gmail,
        senderAccount: testAccount,
        scanFlowMode: flow,
      ),
    );
    await tester.pumpWidget(OneClickScanApp(container: await build()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeKeys.scanAndSend));
    await tester.pumpAndSettle();
  }

  group('flash button', () {
    testWidgets('is not shown when the phone has no flash', (tester) async {
      await pumpScan(tester, flash: false);
      expect(find.byKey(ScanKeys.flashButton), findsNothing);
    });

    testWidgets('top left, Off by default, then Auto, On, Off', (tester) async {
      await pumpScan(tester);
      final button = find.byKey(ScanKeys.flashButton);
      expect(button, findsOneWidget);
      // Top left of the screen, like a camera app.
      expect(tester.getTopLeft(button).dx, lessThan(100));
      expect(tester.getTopLeft(button).dy, lessThan(200));

      Icon icon() => tester.widget<Icon>(
        find.descendant(of: button, matching: find.byType(Icon)),
      );
      expect(icon().icon, Icons.flash_off_rounded);
      expect(find.bySemanticsLabel('Flash: off'), findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(icon().icon, Icons.flash_auto_rounded);
      expect(camera.flashSet.last, FlashMode.auto);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(icon().icon, Icons.flashlight_on_rounded);
      expect(camera.torchLit, isTrue);
      expect(camera.flashSet.last, FlashMode.on);

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(icon().icon, Icons.flash_off_rounded);
      expect(camera.torchLit, isFalse);
    });
  });

  group('tap to focus', () {
    testWidgets('a tap shows the ring and focuses at that point', (
      tester,
    ) async {
      await pumpScan(tester);
      final layer = find.byType(FocusTapLayer);
      final topLeft = tester.getTopLeft(layer);
      final size = tester.getSize(layer);

      await tester.tapAt(topLeft + Offset(size.width * 0.5, size.height * 0.5));
      await tester.pump();

      expect(find.byKey(ScanKeys.focusRing), findsOneWidget);
      expect(camera.focusPoints, hasLength(1));
      expect(camera.focusPoints.single.dx, closeTo(0.5, 0.01));
      expect(camera.focusPoints.single.dy, closeTo(0.5, 0.01));

      // The ring goes away by itself.
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(ScanKeys.focusRing), findsNothing);
    });
  });

  group('low light mark', () {
    testWidgets('appears next to the flash button and goes away', (
      tester,
    ) async {
      await pumpScan(tester);
      expect(find.byKey(ScanKeys.lowLightChip), findsNothing);

      camera.emitSample(FakeLightMeter.dark);
      camera.emitSample(FakeLightMeter.dark);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(ScanKeys.lowLightChip), findsOneWidget);
      expect(find.text('Low light'), findsOneWidget);

      camera.emitSample(FakeLightMeter.bright);
      camera.emitSample(FakeLightMeter.bright);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(ScanKeys.lowLightChip), findsNothing);
    });
  });

  group('dark shot in One Click, Single Page', () {
    testWidgets('the dialog has three choices; New shot leaves nothing', (
      tester,
    ) async {
      await pumpScan(tester);
      meter.fallback = FakeLightMeter.dark;

      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pumpAndSettle();

      expect(find.byKey(ScanKeys.lowLightDialog), findsOneWidget);
      expect(find.byKey(ScanKeys.lowLightRetake), findsOneWidget);
      expect(find.byKey(ScanKeys.lowLightContinue), findsOneWidget);
      expect(find.byKey(ScanKeys.lowLightEnhance), findsOneWidget);
      expect(store.files('pictures'), isEmpty);

      await tester.tap(find.byKey(ScanKeys.lowLightRetake));
      await tester.pumpAndSettle();

      expect(find.byKey(ScanKeys.lowLightDialog), findsNothing);
      expect(find.byKey(ScanKeys.capture), findsOneWidget);
      expect(store.files('pictures'), isEmpty);
      expect(temp.deleted, isNotEmpty);
    });

    testWidgets('Continue anyway stores and goes to the result screen', (
      tester,
    ) async {
      await pumpScan(tester);
      meter.fallback = FakeLightMeter.dark;

      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ScanKeys.lowLightContinue));
      await tester.pumpAndSettle();

      expect(store.files('pictures'), hasLength(1));
      expect(find.byKey(ScanKeys.resultSummary), findsOneWidget);
    });
  });

  group('Multi Page, One Click', () {
    testWidgets('a bar offers a new shot and never blocks the capture', (
      tester,
    ) async {
      await pumpScan(tester);
      await tester.tap(find.text('Multi page'));
      await tester.pumpAndSettle();
      meter.byPath['cache/fake_page_1.jpg'] = FakeLightMeter.dark;

      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pumpAndSettle();

      expect(find.byKey(ScanKeys.darkBar), findsOneWidget);
      expect(find.text('Dark shot: retake?'), findsOneWidget);
      // The capture button is still active: shoot the next page.
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pumpAndSettle();
      expect(find.byKey(ScanKeys.darkBar), findsNothing);
      expect(find.text('Pages: 2'), findsOneWidget);
    });

    testWidgets('Done with a flagged page asks before the send', (
      tester,
    ) async {
      await pumpScan(tester);
      await tester.tap(find.text('Multi page'));
      await tester.pumpAndSettle();
      meter.byPath['cache/fake_page_1.jpg'] = FakeLightMeter.dark;
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ScanKeys.done));
      await tester.pumpAndSettle();

      expect(find.byKey(ScanKeys.lowLightDialog), findsOneWidget);
      expect(find.text('Dark pages'), findsOneWidget);
      expect(store.files('pictures'), isEmpty);

      await tester.tap(find.byKey(ScanKeys.lowLightRetake));
      await tester.pumpAndSettle();
      expect(find.byKey(ScanKeys.lowLightDialog), findsNothing);
      expect(find.text('Pages: 1'), findsOneWidget);
    });
  });

  group('preview banner', () {
    testWidgets('"Correct the light" makes the PDF again', (tester) async {
      await pumpScan(tester, flow: ScanFlowMode.preview);
      meter.fallback = FakeLightMeter.dark;
      rig.engine.respond = (image) => OcrSuccess(
        fakeResult([
          fakeLine(enhancer.targets.contains(image.path) ? 'a b c d' : 'a b'),
        ]),
      );

      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pumpAndSettle();
      // No interruption in the preview mode: straight to the result screen.
      expect(find.byKey(ScanKeys.lowLightDialog), findsNothing);
      expect(find.byKey(ScanKeys.lowLightBanner), findsOneWidget);
      expect(pdf.builder.builds, hasLength(1));

      await tester.tap(find.byKey(ScanKeys.lowLightImprove));
      await tester.pumpAndSettle();

      expect(find.byKey(ScanKeys.lowLightBanner), findsNothing);
      expect(
        find.text('The light was corrected and the PDF was made again.'),
        findsOneWidget,
      );
      expect(pdf.builder.builds, hasLength(2));
    });

    testWidgets('"Keep as is" removes the banner and changes nothing', (
      tester,
    ) async {
      await pumpScan(tester, flow: ScanFlowMode.preview);
      meter.fallback = FakeLightMeter.dark;

      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ScanKeys.lowLightKeep));
      await tester.pumpAndSettle();

      expect(find.byKey(ScanKeys.lowLightBanner), findsNothing);
      expect(pdf.builder.builds, hasLength(1));
      expect(enhancer.sources, isEmpty);
    });

    testWidgets('a bright shot has no banner', (tester) async {
      await pumpScan(tester, flow: ScanFlowMode.preview);

      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pumpAndSettle();

      expect(find.byKey(ScanKeys.lowLightBanner), findsNothing);
    });
  });

  group('torch (ADR-031)', () {
    testWidgets('On: the button shows a lit torch, Off puts it out', (
      tester,
    ) async {
      await pumpScan(tester);
      final button = find.byKey(ScanKeys.flashButton);
      await tester.tap(button); // Auto
      await tester.pumpAndSettle();
      expect(camera.torchLit, isFalse, reason: 'Auto never lights the torch');
      expect(find.bySemanticsLabel('Flash: torch'), findsNothing);

      await tester.tap(button); // On
      await tester.pumpAndSettle();
      expect(camera.torchLit, isTrue);
      expect(find.bySemanticsLabel('Flash: torch'), findsOneWidget);
      final material = tester.widget<Material>(
        find.ancestor(of: button, matching: find.byType(Material)).first,
      );
      expect(
        material.color,
        AppCameraColors.lightFallback.selected,
        reason: 'lit look (the selected colour of the camera chrome)',
      );

      await tester.tap(button); // Off
      await tester.pumpAndSettle();
      expect(camera.torchLit, isFalse);
    });

    testWidgets('the idle timeout puts it out, says so, and goes to Auto', (
      tester,
    ) async {
      await pumpScan(tester);
      final button = find.byKey(ScanKeys.flashButton);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(camera.torchLit, isTrue);

      await tester.pump(const Duration(seconds: 121));
      await tester.pump();

      expect(camera.torchLit, isFalse);
      expect(find.byKey(ScanKeys.torchIdleOff), findsOneWidget);
      expect(
        find.textContaining('does not get warm'),
        findsOneWidget,
        reason: 'the short message of the idle timeout',
      );
      expect(
        tester
            .widget<Icon>(
              find.descendant(of: button, matching: find.byType(Icon)),
            )
            .icon,
        Icons.flash_auto_rounded,
      );
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('a very dark shot: the retake comes first, the rest stays', (
      tester,
    ) async {
      await pumpScan(tester);
      meter.fallback = FakeLightMeter.dark;

      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pumpAndSettle();

      expect(find.textContaining('very dark'), findsOneWidget);
      expect(
        tester.widget(find.byKey(ScanKeys.lowLightRetake)),
        isA<FilledButton>(),
        reason: 'the retake is the primary choice',
      );
      expect(find.byKey(ScanKeys.lowLightContinue), findsOneWidget);
      expect(find.byKey(ScanKeys.lowLightEnhance), findsOneWidget);
    });

    testWidgets('the preview banner advises the retake for a very dark page', (
      tester,
    ) async {
      await pumpScan(tester, flow: ScanFlowMode.preview);
      meter.fallback = FakeLightMeter.dark;

      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pumpAndSettle();

      expect(find.byKey(ScanKeys.lowLightBanner), findsOneWidget);
      expect(find.textContaining('very dark'), findsOneWidget);
      expect(find.byKey(ScanKeys.lowLightBannerRetake), findsOneWidget);
      expect(find.byKey(ScanKeys.lowLightImprove), findsOneWidget);
      expect(find.byKey(ScanKeys.lowLightKeep), findsOneWidget);
    });
  });
}
