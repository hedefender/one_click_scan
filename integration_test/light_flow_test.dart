import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/core/logging/app_logger.dart';
import 'package:one_click_scan/domain/entities/captured_page.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/scan_flow_mode.dart';
import 'package:one_click_scan/domain/ocr/ocr_language_pack_registry.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/scan/scan_keys.dart';
import 'package:one_click_scan/services/ocr/ocr_services.dart';
import 'package:one_click_scan/services/pdf/pdf_services.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/fakes.dart';
import '../test/support/mail_fakes.dart';
import '../test/support/pdf_fakes.dart';
import '../test/support/scan_fakes.dart';
import 'support/directory_scan_file_store.dart';
import 'support/synthetic_pages.dart';

/// Phase 6.2 on the Claude Code emulator: a dark shot in the flow, with the
/// real OCR, the real PDF writer, the real light meter (native decode and an
/// isolate), the real light correction (`flat`, isolate) and a real directory
/// as the user's folder. The photos are an invented receipt, bright and
/// darkened.
///
/// NOT tested here (the emulator cannot): the real flash, the real light of a
/// room, the focus of a real lens. Those are in `PHASE_6_2_VALIDATION.md` for
/// the phone. Run on the Claude Code emulator only:
///   tool/run_integration_test.sh `<emulator-id>` integration_test/light_flow_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const account = 'user@example.test';

  late Directory cache;
  late Directory work;
  late OcrServices ocr;
  late PdfServices pdf;
  late Directory ocrWork;
  late List<int> brightJpeg;
  late List<int> darkJpeg;
  late DirectoryScanFileStore folder;
  late CapturingLogger logger;
  late MailTestRig mail;

  void report(String message) {
    // ignore: avoid_print
    print('LIGHTIT $message');
  }

  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(minutes: 4),
  }) async {
    final end = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) fail('Timed out waiting for $finder');
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  List<File> cacheFiles() => ocrWork.existsSync()
      ? ocrWork.listSync(recursive: true).whereType<File>().toList()
      : <File>[];

  List<File> files(String sub) {
    final dir = Directory('${folder.root.path}/$sub');
    // `.nomedia` is the folder's own marker, not a file of the scan.
    return dir.existsSync()
        ? dir
              .listSync()
              .whereType<File>()
              .where((f) => !f.path.split('/').last.startsWith('.'))
              .toList()
        : <File>[];
  }

  String digest(List<int> bytes) => sha256.convert(bytes).toString();

  Future<_ShotCamera> startApp(
    WidgetTester tester, {
    required ScanFlowMode mode,
    required List<List<int>> shots,
    bool multi = false,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    folder = DirectoryScanFileStore(
      Directory('${work.path}/folder')..createSync(recursive: true),
    );
    logger = CapturingLogger();
    mail = MailTestRig()..storePassword(account: account);
    final camera = _ShotCamera(
      Directory('${work.path}/shots_${DateTime.now().microsecondsSinceEpoch}')
        ..createSync(recursive: true),
      shots,
    );
    final container = await buildTestContainer(
      camera: camera,
      scanFileStore: folder,
      scanTempStore: FakeScanTempStore(),
      gallery: FakeGalleryService(),
      ocr: ocr,
      pdf: PdfServices(builder: pdf.builder, opener: FakeOpenPdf()),
      mail: mail.services,
      logger: logger,
    );
    final repository = container<SettingsRepository>();
    await repository.save(
      (await repository.load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        ocrPackId: OcrPackIds.greek,
        mailProvider: MailProviderId.gmail,
        senderAccount: account,
        saveToGallery: false,
        scanFlowMode: mode,
      ),
    );
    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeKeys.scanAndSend));
    await tester.pumpAndSettle();
    if (multi) {
      await tester.tap(find.text('Multi page'));
      await tester.pumpAndSettle();
    }
    return camera;
  }

  setUpAll(() async {
    cache = await getTemporaryDirectory();
    work = Directory('${cache.path}/light_it')..createSync(recursive: true);
    ocrWork = Directory('${cache.path}/ocr_work');
    ocr = await createPlatformOcrServices(
      registry: OcrLanguagePackRegistry.standard,
      logger: const DebugAppLogger(),
    );
    pdf = await createPlatformPdfServices(logger: const DebugAppLogger());
    final flat = await renderDocument(greekReceipt.lines);
    // A phone photo is bigger than the drawing: 1536 x 2048 on a grey table.
    final photo = img.Image(width: 1536, height: 2048, numChannels: 3);
    img.fill(photo, color: img.ColorRgb8(238, 238, 238));
    img.compositeImage(
      photo,
      img.copyResize(flat, width: 1200),
      dstX: 168,
      dstY: 200,
    );
    brightJpeg = img.encodeJpg(photo, quality: 92);
    // The same shot at about a quarter of the light.
    final dark = img.adjustColor(photo, brightness: 0.28);
    darkJpeg = img.encodeJpg(dark, quality: 92);
  });

  tearDownAll(() async {
    await ocr.engine.dispose();
    await ocr.workStore.purgeAll();
    await pdf.builder.purgeAll();
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  tearDown(() {
    final dir = Directory('${work.path}/folder');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('One Click, Single: a dark shot stops the flow; New shot leaves '
      'nothing, a bright one then goes through', (tester) async {
    await startApp(
      tester,
      mode: ScanFlowMode.oneClick,
      shots: [darkJpeg, brightJpeg],
    );

    await tester.tap(find.byKey(ScanKeys.capture));
    await pumpUntil(tester, find.byKey(ScanKeys.lowLightDialog));
    expect(
      files('pictures'),
      isEmpty,
      reason: 'nothing stored before the answer',
    );

    await tester.tap(find.byKey(ScanKeys.lowLightRetake));
    await tester.pumpAndSettle();
    expect(find.byKey(ScanKeys.lowLightDialog), findsNothing);
    expect(files('pictures'), isEmpty);
    expect(files('pdf'), isEmpty);
    expect(mail.sender.sent, isEmpty);

    // The second shot is bright: no question, the whole flow runs.
    await tester.tap(find.byKey(ScanKeys.capture));
    await pumpUntil(tester, find.byKey(ScanKeys.autoReturn));
    expect(find.byKey(ScanKeys.lowLightDialog), findsNothing);
    expect(mail.sender.sent, hasLength(1));
    report('single: dark shot asked, retake left no file, bright one sent');
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets('One Click, Single: Continue anyway sends the dark shot, the '
      'original byte for byte', (tester) async {
    await startApp(tester, mode: ScanFlowMode.oneClick, shots: [darkJpeg]);

    await tester.tap(find.byKey(ScanKeys.capture));
    await pumpUntil(tester, find.byKey(ScanKeys.lowLightDialog));
    await tester.tap(find.byKey(ScanKeys.lowLightContinue));
    await pumpUntil(tester, find.byKey(ScanKeys.autoReturn));

    final stored = files('pictures');
    expect(stored, hasLength(1));
    expect(digest(stored.single.readAsBytesSync()), digest(darkJpeg));
    expect(mail.sender.sent, hasLength(1));
    expect(
      logger.lines.where((l) => l.contains('Light correction')),
      isEmpty,
      reason: 'no correction unless the user asked',
    );
    expect(cacheFiles(), isEmpty);
    report('single: continue anyway sent the dark shot unchanged');
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets('One Click, Single: Continue with correction applies flat with '
      'the safety valve', (tester) async {
    await startApp(tester, mode: ScanFlowMode.oneClick, shots: [darkJpeg]);

    await tester.tap(find.byKey(ScanKeys.capture));
    await pumpUntil(tester, find.byKey(ScanKeys.lowLightDialog));
    await tester.tap(find.byKey(ScanKeys.lowLightEnhance));
    await pumpUntil(tester, find.byKey(ScanKeys.autoReturn));

    final stored = files('pictures');
    expect(digest(stored.single.readAsBytesSync()), digest(darkJpeg));
    final line = logger.lines.where((l) => l.contains('Light correction'));
    expect(line, isNotEmpty, reason: 'the correction ran and was judged');
    expect(files('pdf'), hasLength(1));
    expect(mail.sender.sent, hasLength(1));
    expect(cacheFiles(), isEmpty);
    report('single: ${line.first}');
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets('One Click, Multi: Done asks before the send when a page is '
      'dark', (tester) async {
    await startApp(
      tester,
      mode: ScanFlowMode.oneClick,
      shots: [brightJpeg, darkJpeg],
      multi: true,
    );
    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pump(const Duration(milliseconds: 300));
    await pumpUntil(tester, find.byKey(ScanKeys.capture));
    await tester.tap(find.byKey(ScanKeys.capture));
    await pumpUntil(tester, find.byKey(ScanKeys.darkBar));
    expect(find.byKey(ScanKeys.capture), findsOneWidget);

    await tester.tap(find.byKey(ScanKeys.done));
    await pumpUntil(tester, find.byKey(ScanKeys.lowLightDialog));
    expect(mail.sender.sent, isEmpty, reason: 'not sent silently');
    expect(files('pictures'), isEmpty);

    await tester.tap(find.byKey(ScanKeys.lowLightContinue));
    await pumpUntil(tester, find.byKey(ScanKeys.autoReturn));
    expect(files('pictures'), hasLength(2));
    expect(mail.sender.sent, hasLength(1));
    report('multi: summary asked before the send, then sent');
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets('Preview: the banner, the correction, the PDF made again, and '
      'Discard cleans everything', (tester) async {
    await startApp(tester, mode: ScanFlowMode.preview, shots: [darkJpeg]);

    await tester.tap(find.byKey(ScanKeys.capture));
    await pumpUntil(tester, find.byKey(ScanKeys.lowLightBanner));
    await pumpUntil(tester, find.byKey(ScanKeys.discard));
    final pdfBefore = files('pdf').single.lengthSync();
    expect(mail.sender.sent, isEmpty);

    await tester.ensureVisible(find.byKey(ScanKeys.lowLightImprove));
    await tester.tap(find.byKey(ScanKeys.lowLightImprove));
    await pumpUntil(tester, find.byKey(ScanKeys.lowLightStatus));
    // The correction runs (two readings of the page), then the PDF is made
    // again or kept: wait until the status is no longer "working".
    final end = DateTime.now().add(const Duration(minutes: 3));
    while (find.text('Correcting the light…').evaluate().isNotEmpty) {
      if (DateTime.now().isAfter(end)) fail('the correction did not end');
      await tester.pump(const Duration(milliseconds: 200));
    }
    await pumpUntil(tester, find.byKey(ScanKeys.discard));
    await tester.pump(const Duration(seconds: 2));

    // The PDF exists again (made again, or kept when the correction did not
    // help), the original is untouched.
    expect(files('pdf'), hasLength(1));
    expect(
      digest(files('pictures').single.readAsBytesSync()),
      digest(darkJpeg),
    );
    final status = tester
        .widget<Text>(find.byKey(ScanKeys.lowLightStatus))
        .data;
    report(
      'preview: status "$status", PDF $pdfBefore -> '
      '${files('pdf').single.lengthSync()} bytes',
    );

    await tester.ensureVisible(find.byKey(ScanKeys.discard));
    await tester.tap(find.byKey(ScanKeys.discard));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ScanKeys.discardConfirm));
    await pumpUntil(tester, find.text('The scan was deleted.'));
    expect(files('pictures'), isEmpty);
    expect(files('pdf'), isEmpty);
    expect(cacheFiles(), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 8)));
}

/// Gives the invented photos, one after the other, as the shots of the camera.
class _ShotCamera extends FakeCameraService {
  _ShotCamera(this.dir, this.images);

  final Directory dir;
  final List<List<int>> images;
  final List<File> shots = [];
  var _n = 0;

  @override
  Future<CapturedPage> capture({required int order}) async {
    final file = File('${dir.path}/shot_$_n.jpg')
      ..writeAsBytesSync(images[_n % images.length]);
    _n++;
    shots.add(file);
    return CapturedPage(path: file.path, order: order);
  }
}
