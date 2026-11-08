import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/core/config/app_config.dart';
import 'package:one_click_scan/domain/entities/captured_page.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/scan_flow_mode.dart';
import 'package:one_click_scan/domain/lighting/light_metric.dart';
import 'package:one_click_scan/domain/mail/mail_outcome.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/first_run/first_run_keys.dart';
import 'package:one_click_scan/features/help/help_keys.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/scan/scan_keys.dart';
import 'package:one_click_scan/features/settings/settings_keys.dart';
import 'package:one_click_scan/presentation/guide/guide_view.dart';
import 'package:one_click_scan/presentation/l10n/guide_section.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/fakes.dart';
import '../test/support/mail_fakes.dart';
import '../test/support/ocr_fakes.dart';
import '../test/support/pdf_fakes.dart';
import '../test/support/scan_fakes.dart';
import 'support/synthetic_pages.dart';

/// Phase 6.3.1: a screenshot of every screen of the app, in the light and the
/// dark theme, in Greek, for people who design the look of the app.
///
/// **Only invented data.** The account is `demo@example.test`, the "receipt" is
/// drawn here with made-up items (no name, no address, no card number) and
/// every adapter is a fake (the same fakes as the widget tests): the camera
/// shows that drawing, the OCR, the PDF writer and the mail sender are
/// scripted, nothing is sent. No production code is changed for this.
///
/// What it captures is the Flutter surface (the app), without the Android
/// status bar and navigation bar, so no clock, notification or battery is in
/// the pictures. The theme is set with the platform brightness of the test
/// binding, which the app reads exactly like the device theme.
///
/// The pictures are written to `files/shots/` of the app; the runner
/// `tool/run_screenshots.sh` copies them to `build/screenshots/light` and
/// `build/screenshots/dark`:
///   tool/run_screenshots.sh `<emulator-id>`
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const demo = 'demo@example.test';

  late Directory out;
  late Directory work;
  late Uint8List previewPng;
  late Uint8List shotJpeg;

  // The pages of the invented receipt: nothing that could be a person.
  const receiptLines = [
    'ΔΟΚΙΜΑΣΤΙΚΗ ΑΠΟΔΕΙΞΗ',
    'Κατάστημα Παράδειγμα',
    'Ημερομηνία 12/03/2026',
    'Γάλα φρέσκο 1 λίτρο   1,45',
    'Ψωμί ολικής άλεσης   2,30',
    'Ελαιόλαδο 500 ml   7,90',
    'Μήλα 1 κιλό   2,10',
    'Σύνολο   13,75 EUR',
    'Ευχαριστούμε',
  ];

  var theme = 'light';
  var shots = 0;

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 400));
    final bytes = await binding.takeScreenshot('${theme}_$name');
    File('${out.path}/${theme}_$name.png').writeAsBytesSync(bytes);
    shots++;
    // ignore: avoid_print
    print('SHOT ${theme}_$name (${bytes.length} bytes)');
  }

  setUpAll(() async {
    final support = await getApplicationSupportDirectory();
    out = Directory('${support.path}/shots')..createSync(recursive: true);
    for (final f in out.listSync().whereType<File>()) {
      f.deleteSync();
    }
    work = Directory('${(await getTemporaryDirectory()).path}/shots_work')
      ..createSync(recursive: true);
    final page = await renderDocument(receiptLines, width: 1000, fontSize: 40);
    final photo = img.Image(width: 1536, height: 2048, numChannels: 3);
    img.fill(photo, color: img.ColorRgb8(70, 74, 82));
    img.compositeImage(
      photo,
      img.copyResize(page, width: 1200),
      dstX: 168,
      dstY: 260,
    );
    previewPng = Uint8List.fromList(img.encodePng(photo));
    shotJpeg = Uint8List.fromList(img.encodeJpg(photo, quality: 90));
    await binding.convertFlutterSurfaceToImage();
  });

  tearDownAll(() async {
    // Time for the runner to copy the last pictures before the app goes.
    await Future<void>.delayed(const Duration(seconds: 8));
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  Future<void> systemBack(WidgetTester tester) async {
    final message = const JSONMethodCodec().encodeMethodCall(
      const MethodCall('popRoute'),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      message,
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  /// The fakes answer in real time on the device: wait until [finder] shows.
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) fail('Timed out waiting for $finder');
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  Future<void> shoot(WidgetTester tester, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
    }
  }

  Future<_Rig> start(
    WidgetTester tester, {
    ScanFlowMode flow = ScanFlowMode.oneClick,
    bool hintSeen = true,
    bool atCamera = true,
    int pageBytes = 1800000,
    bool dark = false,
  }) async {
    final rig = _Rig(
      Directory('${work.path}/cam_${DateTime.now().microsecondsSinceEpoch}')
        ..createSync(recursive: true),
      previewPng,
      shotJpeg,
    );
    rig.ocr.workStore.defaultBytes = pageBytes;
    if (dark) rig.meter.fallback = FakeLightMeter.dark;
    rig.mail.storePassword(account: demo);
    Future<GetIt> build() => buildTestContainer(
      config: AppConfig.forDeviceLanguage('el'),
      store: rig.kv,
      camera: rig.camera,
      scanFileStore: rig.store,
      scanTempStore: FakeScanTempStore(),
      gallery: FakeGalleryService(),
      ocr: rig.ocr.services,
      lightMeter: rig.meter,
      pdf: rig.pdf.services,
      mail: rig.mail.services,
      multiHintSeen: hintSeen,
    );
    final seed = await build();
    await seed<SettingsRepository>().save(
      (await seed<SettingsRepository>().load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        mailProvider: MailProviderId.gmail,
        senderAccount: demo,
        saveToGallery: false,
        scanFlowMode: flow,
      ),
    );
    // A fresh app: the router of the scenario before must not be reused.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(OneClickScanApp(container: await build()));
    await tester.pumpAndSettle();
    if (atCamera) {
      await tester.tap(find.byKey(HomeKeys.scanAndSend));
      await tester.pumpAndSettle();
    }
    return rig;
  }

  Future<void> wizard(WidgetTester tester) async {
    final kv = InMemoryKeyValueStore();
    final container = await buildTestContainer(
      config: AppConfig.forDeviceLanguage('el'),
      store: kv,
      multiHintSeen: true,
    );
    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();
    await shot(tester, '01_wizard_welcome');
    await tapKey(tester, FirstRunKeys.next);
    await tapKey(tester, FirstRunKeys.pickFolder);
    await shot(tester, '02_wizard_folder');
    await tapKey(tester, FirstRunKeys.next);
    await tester.tap(find.text('Gmail'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(FirstRunKeys.sender), demo);
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await shot(tester, '03_wizard_provider');
    await tapKey(tester, FirstRunKeys.next);
    await shot(tester, '04_wizard_gallery');
    await tapKey(tester, FirstRunKeys.next);
    await tapKey(tester, FirstRunKeys.flowPreview);
    await shot(tester, '05_wizard_flow');
    await tapKey(tester, FirstRunKeys.next);
    await shot(tester, '06_wizard_guide');
    // The end of the page, with the last line.
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -3000),
    );
    await tester.pumpAndSettle();
    await shot(tester, '07_wizard_guide_end');
  }

  Future<void> cameraStates(WidgetTester tester) async {
    var rig = await start(tester);
    await shot(tester, '10_camera_single');
    await tapKey(tester, ScanKeys.flashButton);
    await shot(tester, '13_flash_auto');
    await tapKey(tester, ScanKeys.flashButton);
    await tester.pump(const Duration(milliseconds: 700));
    await shot(tester, '14_flash_on_torch');
    await tapKey(tester, ScanKeys.flashButton);
    await shot(tester, '12_flash_off');
    for (var i = 0; i < 3; i++) {
      rig.camera.emitSample(const LightMetric(paper: 18, contrast: 10));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 600));
    await shot(tester, '15_lowlight_mark');

    rig = await start(tester);
    await tester.tap(find.text('Πολλές σελίδες'));
    await tester.pumpAndSettle();
    await shoot(tester, times: 2);
    await shot(tester, '11a_camera_multi_pages');
    await shoot(tester, times: 4);
    await shot(tester, '11_camera_multi_counter');

    // Back with pages: "Stay / Discard".
    await systemBack(tester);
    await shot(tester, '31_dialog_stay_discard');
  }

  Future<void> lowLight(WidgetTester tester) async {
    var rig = await start(tester, dark: true);
    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    await shot(tester, '16_lowlight_dialog');
    expect(rig.mail.sender.sent, isEmpty);

    rig = await start(tester, flow: ScanFlowMode.preview, dark: true);
    await shoot(tester);
    await waitFor(tester, find.byKey(ScanKeys.lowLightBanner));
    await shot(tester, '17_lowlight_banner');

    rig = await start(tester, dark: true);
    await tester.tap(find.text('Πολλές σελίδες'));
    await tester.pumpAndSettle();
    await shoot(tester, times: 2);
    await tester.tap(find.byKey(ScanKeys.done));
    await tester.pumpAndSettle();
    await shot(tester, '33_multi_summary');
    expect(rig.mail.sender.sent, isEmpty);
  }

  Future<void> flowStates(WidgetTester tester) async {
    var rig = await start(tester);
    rig.ocr.engine.gate = Completer<void>();
    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await shot(tester, '20_progress_reading');
    rig.ocr.engine.gate!.complete();
    await tester.pumpAndSettle();

    rig = await start(tester);
    rig.pdf.builder.gate = Completer<void>();
    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await shot(tester, '21_progress_pdf');
    rig.pdf.builder.gate!.complete();
    await tester.pumpAndSettle();

    rig = await start(tester);
    final hold = Completer<MailOutcome>();
    rig.mail.sender.hold = hold;
    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await shot(tester, '22_progress_sending');
    hold.complete(const MailSent());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await shot(tester, '23_success_countdown');
    await tester.pumpAndSettle(const Duration(seconds: 15));

    rig = await start(tester, atCamera: true);
    rig.mail.sender.outcome = const MailNetworkError();
    await shoot(tester);
    await shot(tester, '24_send_failed');
  }

  Future<void> preview(WidgetTester tester) async {
    final rig = await start(tester, flow: ScanFlowMode.preview);
    await shoot(tester);
    await waitFor(
      tester,
      find.byWidgetPredicate(
        (w) =>
            w.key == ScanKeys.pdfDetails ||
            w.key == ScanKeys.mailSend ||
            w.key == ScanKeys.discard,
      ),
    );
    await shot(tester, '30_preview');
    await tester.scrollUntilVisible(
      find.byKey(ScanKeys.discard),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tapKey(tester, ScanKeys.discard);
    await shot(tester, '32_discard_confirm');
    expect(rig.mail.sender.sent, isEmpty);
  }

  Future<void> settingsAndHelp(WidgetTester tester) async {
    await start(tester, atCamera: false);
    await shot(tester, '09_home');
    await tester.tap(find.byKey(HomeKeys.settings));
    await tester.pumpAndSettle();
    await shot(tester, '40_settings_top');
    final list = find.byType(Scrollable).first;
    await tester.drag(list, const Offset(0, -900));
    await tester.pumpAndSettle();
    await shot(tester, '41_settings_middle');
    await tester.scrollUntilVisible(
      find.byKey(SettingsKeys.helpEntry),
      300,
      scrollable: list,
    );
    await shot(tester, '41a_settings_end');
    await tester.tap(find.byKey(SettingsKeys.helpEntry));
    await tester.pumpAndSettle();
    await shot(tester, '42_help_top');
    await tester.scrollUntilVisible(
      find.byKey(GuideKeys.section(GuideSectionId.notCovered)),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await shot(tester, '43_help_section');
    expect(find.byKey(HelpKeys.page), findsOneWidget);
  }

  Future<void> multiHint(WidgetTester tester) async {
    await start(tester, hintSeen: false);
    await tester.tap(find.text('Πολλές σελίδες'));
    await tester.pumpAndSettle();
    await shot(tester, '44_multi_hint');
  }

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('screenshots, ${brightness.name} theme', (tester) async {
      theme = brightness.name;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await wizard(tester);
      await cameraStates(tester);
      await lowLight(tester);
      await flowStates(tester);
      await preview(tester);
      await settingsAndHelp(tester);
      await multiHint(tester);
      // ignore: avoid_print
      print('SHOTS $theme done, total so far $shots');
    }, timeout: const Timeout(Duration(minutes: 12)));
  }
}

/// All the fakes of one scenario, with the camera that shows the invented
/// receipt (a preview and real JPEG files for the thumbnails).
class _Rig {
  _Rig(Directory dir, Uint8List preview, Uint8List jpeg)
    : camera = _DemoCamera(dir, preview, jpeg);

  final _DemoCamera camera;
  final ocr = OcrTestRig();
  final pdf = PdfTestRig();
  final mail = MailTestRig();
  final store = FakeScanFileStore();
  final meter = FakeLightMeter();
  final kv = InMemoryKeyValueStore();
}

class _DemoCamera extends FakeCameraService {
  _DemoCamera(this.dir, this.preview, this.jpeg) : super(flashAvailable: true);

  final Directory dir;
  final Uint8List preview;
  final Uint8List jpeg;
  var _n = 0;

  @override
  Widget buildPreview(BuildContext context) =>
      Image.memory(preview, fit: BoxFit.cover, width: double.infinity);

  @override
  Future<CapturedPage> capture({required int order}) async {
    final file = File('${dir.path}/shot_${_n++}.jpg')..writeAsBytesSync(jpeg);
    return CapturedPage(path: file.path, order: order);
  }
}
