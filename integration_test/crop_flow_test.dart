import 'dart:convert';
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
import '../test/support/synth/scene.dart';
import 'support/directory_scan_file_store.dart';
import 'support/synthetic_pages.dart';

/// Phase 6.1 on the Claude Code emulator: the crop and the straightening of the
/// page (ADR-029) with the real OCR, the real PDF writer, the real isolate of
/// the crop and a real directory as the user's folder. The photos are invented
/// scenes (a receipt drawn on a table, tilted, with a dark background, and a
/// table with no document) made with the generator of the unit tests.
///
/// What it checks (asserted): the originals in the folder are byte for byte the
/// photos of the camera; the PDF page of a straightened photo has the ratio of
/// the receipt and the page of the table with no document keeps the whole
/// frame; the preview shows the pages and keeps their files only until the
/// scan is discarded; One Click leaves nothing in the cache; a Cancel in the
/// middle leaves nothing in the cache. What it measures (printed as `CROPIT`
/// lines, nothing asserted): the time after "Done" and the memory for 5 and 21
/// pages, back to back and one every 2.5 s. An x86 emulator says nothing about
/// the speed of a phone. The PDFs are kept in `pdf_it/` for the PC (the text
/// layer is checked with tool/check_pdf_text.py). Run on the Claude Code
/// emulator only:
///   tool/run_pdf_integration_test.sh `<emulator-id>` build/crop_it integration_test/crop_flow_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const account = 'user@example.test';

  late Directory cache;
  late Directory support;
  late Directory out; // pulled by the runner script
  late Directory work;
  late PdfServices pdf;
  late OcrServices ocr;
  late Directory ocrWork;
  late List<img.Image> scenes; // tilted, dark background, no document
  late double flatAspect;
  late DirectoryScanFileStore folder;
  late CapturingLogger logger;

  void report(String message) {
    // ignore: avoid_print
    print('CROPIT $message');
  }

  String mb(int bytes) => '${(bytes / (1024 * 1024)).round()} MB';

  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(minutes: 6),
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

  /// The size ratio (width / height) of every page of a PDF, from its
  /// `/MediaBox` entries.
  List<double> pageRatios(File file) {
    final text = latin1.decode(file.readAsBytesSync());
    return [
      for (final m in RegExp(
        r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]',
      ).allMatches(text))
        double.parse(m.group(1)!) / double.parse(m.group(2)!),
    ];
  }

  String digest(File file) => sha256.convert(file.readAsBytesSync()).toString();

  Future<void> startApp(
    WidgetTester tester, {
    required ScanFlowMode mode,
    required _SceneCamera camera,
    bool multiPage = true,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    folder = DirectoryScanFileStore(
      Directory('${work.path}/folder')..createSync(recursive: true),
    );
    logger = CapturingLogger();
    final rig = MailTestRig()..storePassword(account: account);
    final container = await buildTestContainer(
      camera: camera,
      scanFileStore: folder,
      scanTempStore: FakeScanTempStore(),
      gallery: FakeGalleryService(),
      ocr: ocr,
      pdf: PdfServices(builder: pdf.builder, opener: FakeOpenPdf()),
      mail: rig.services,
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
    if (multiPage) {
      await tester.tap(find.text('Multi page'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> shoot(WidgetTester tester, int count, {Duration? every}) async {
    for (var i = 0; i < count; i++) {
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pump(const Duration(milliseconds: 100));
      await pumpUntil(tester, find.byKey(ScanKeys.capture));
      if (every != null) {
        final end = DateTime.now().add(every);
        while (DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
    }
  }

  setUpAll(() async {
    cache = await getTemporaryDirectory();
    support = await getApplicationSupportDirectory();
    out = Directory('${support.path}/pdf_it')..createSync(recursive: true);
    work = Directory('${cache.path}/crop_it')..createSync(recursive: true);
    ocrWork = Directory('${cache.path}/ocr_work');
    ocr = await createPlatformOcrServices(
      registry: OcrLanguagePackRegistry.standard,
      logger: const DebugAppLogger(),
    );
    pdf = await createPlatformPdfServices(logger: const DebugAppLogger());
    final flat = await renderDocument(greekReceipt.lines);
    flatAspect = flat.width / flat.height;
    final page = FlatPage.fromImage(flat);
    SceneSpec spec(
      String id,
      int seed, {
      double tiltXDeg = 0,
      double tiltYDeg = 0,
      double rollDeg = 0,
      Background background = Background.table,
      bool hasDocument = true,
    }) => SceneSpec(
      id: id,
      category: id,
      document: 'greek',
      seed: seed,
      width: 1536,
      height: 2048,
      tiltXDeg: tiltXDeg,
      tiltYDeg: tiltYDeg,
      rollDeg: rollDeg,
      fill: 0.8,
      background: background,
      hasDocument: hasDocument,
    );
    scenes = [
      renderScene(spec('tilted', 11, tiltYDeg: 15, rollDeg: 6), page).image,
      renderScene(
        spec('dark', 12, tiltXDeg: 8, rollDeg: -4, background: Background.dark),
        page,
      ).image,
      renderScene(spec('empty', 13, hasDocument: false), page).image,
    ];
  });

  tearDownAll(() async {
    await ocr.engine.dispose();
    await ocr.workStore.purgeAll();
    await pdf.builder.purgeAll();
    if (work.existsSync()) work.deleteSync(recursive: true);
    // Time for the runner to pull the last files.
    await Future<void>.delayed(const Duration(seconds: 7));
  });

  tearDown(() {
    final dir = Directory('${work.path}/folder');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('preview: straightened and whole-frame pages in the PDF, the '
      'originals unchanged, the cache emptied by Discard', (tester) async {
    final camera = _SceneCamera(
      Directory('${work.path}/shots_preview')..createSync(recursive: true),
      scenes,
    );
    await startApp(tester, mode: ScanFlowMode.preview, camera: camera);
    await shoot(tester, 3);
    await tester.tap(find.byKey(ScanKeys.done));
    await tester.pump();
    await pumpUntil(tester, find.byKey(ScanKeys.discard));

    // The originals: byte for byte the photos of the camera.
    final stored =
        (Directory('${folder.root.path}/pictures')
                .listSync()
                .whereType<File>()
                .where((f) => f.path.endsWith('.jpg'))
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path)))
            .map(digest)
            .toList();
    expect(stored, camera.shots.map(digest).toList());

    // The preview shows the pages as they are in the PDF.
    expect(find.byKey(ScanKeys.pdfPages), findsOneWidget);
    expect(find.byKey(ScanKeys.pdfPage(2)), findsOneWidget);
    expect(cacheFiles(), hasLength(3), reason: 'one working file per page');

    // The pages of the PDF.
    final pdfFile = Directory('${folder.root.path}/pdf')
        .listSync()
        .whereType<File>()
        .single;
    final ratios = pageRatios(pdfFile);
    expect(ratios, hasLength(3));
    expect(
      ratios[0],
      closeTo(flatAspect, flatAspect * 0.06),
      reason: 'the tilted receipt is cut and straightened',
    );
    expect(
      ratios[2],
      closeTo(1536 / 2048, 0.02),
      reason: 'a table with no document keeps the whole frame',
    );
    final cropLine = logger.lines.where((l) => l.contains('Page crop:'));
    report(
      'preview, 3 pages: PDF page ratios '
      '${ratios.map((r) => r.toStringAsFixed(3)).toList()} (receipt '
      '${flatAspect.toStringAsFixed(3)}, frame 0.750); '
      '${cropLine.isEmpty ? 'no crop line' : cropLine.first}',
    );
    File(pdfFile.path).copySync('${out.path}/crop_preview.pdf');
    await Future<void>.delayed(const Duration(seconds: 7));

    // Discard deletes the originals and, with the session, the cache files.
    await tester.ensureVisible(find.byKey(ScanKeys.discard));
    await tester.tap(find.byKey(ScanKeys.discard));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ScanKeys.discardConfirm));
    await pumpUntil(tester, find.text('The scan was deleted.'));
    expect(
      cacheFiles(),
      isEmpty,
      reason: 'no picture of a document stays in the cache after Discard',
    );
  }, timeout: const Timeout(Duration(minutes: 10)));

  testWidgets('One Click: one message, nothing left in the cache, the '
      'originals unchanged', (tester) async {
    final camera = _SceneCamera(
      Directory('${work.path}/shots_oneclick')..createSync(recursive: true),
      scenes,
    );
    await startApp(tester, mode: ScanFlowMode.oneClick, camera: camera);
    await shoot(tester, 3);
    await tester.tap(find.byKey(ScanKeys.done));
    await tester.pump();
    await pumpUntil(tester, find.byKey(ScanKeys.autoReturn));

    final pictures =
        (Directory('${folder.root.path}/pictures')
                .listSync()
                .whereType<File>()
                .where((f) => f.path.endsWith('.jpg'))
                .toList()
              ..sort((a, b) => a.path.compareTo(b.path)))
            .map(digest)
            .toList();
    expect(pictures, camera.shots.map(digest).toList());
    expect(cacheFiles(), isEmpty, reason: 'One Click keeps no working copy');
    final pdfFile = Directory('${folder.root.path}/pdf')
        .listSync()
        .whereType<File>()
        .single;
    expect(pageRatios(pdfFile), hasLength(3));
    expect(find.byKey(ScanKeys.pdfPages), findsNothing);
    report('one click, 3 pages: PDF ${pdfFile.lengthSync()} bytes');
    File(pdfFile.path).copySync('${out.path}/crop_oneclick.pdf');
    await Future<void>.delayed(const Duration(seconds: 7));
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets('Cancel while the pages are processed leaves no file in the '
      'cache', (tester) async {
    final camera = _SceneCamera(
      Directory('${work.path}/shots_cancel')..createSync(recursive: true),
      scenes,
    );
    await startApp(tester, mode: ScanFlowMode.preview, camera: camera);
    await shoot(tester, 5);
    await tester.tap(find.byKey(ScanKeys.done));
    await tester.pump(const Duration(milliseconds: 300));
    await pumpUntil(tester, find.byKey(ScanKeys.flowCancel));
    await tester.tap(find.byKey(ScanKeys.flowCancel));
    await pumpUntil(tester, find.byKey(ScanKeys.flowCancelled));
    // The isolate of a crop that was running is killed and its file removed.
    await tester.pump(const Duration(seconds: 3));
    expect(cacheFiles(), isEmpty);
    report('cancel with 5 pages: cache empty');
  }, timeout: const Timeout(Duration(minutes: 8)));

  for (final spec in [(5, null), (21, null), (5, 2500), (21, 2500)]) {
    final pages = spec.$1;
    final pace = spec.$2;
    final label = pace == null ? 'back to back' : 'every ${pace / 1000} s';
    testWidgets('measure: $pages pages, $label', (tester) async {
      final camera = _SceneCamera(
        Directory('${work.path}/shots_m${pages}_${pace ?? 0}')
          ..createSync(recursive: true),
        [scenes.first],
      );
      await startApp(tester, mode: ScanFlowMode.preview, camera: camera);
      final rssStart = ProcessInfo.currentRss;
      final capture = Stopwatch()..start();
      await shoot(
        tester,
        pages,
        every: pace == null ? null : Duration(milliseconds: pace),
      );
      capture.stop();

      final afterDone = Stopwatch()..start();
      await tester.tap(find.byKey(ScanKeys.done));
      await tester.pump();
      await pumpUntil(tester, find.byKey(ScanKeys.resultSummary));
      final saveMs = afterDone.elapsedMilliseconds;
      await pumpUntil(tester, find.byKey(ScanKeys.discard));
      final totalMs = afterDone.elapsedMilliseconds;
      final rssEnd = ProcessInfo.currentRss;
      final rssPeak = ProcessInfo.maxRss;
      final pdfFile = Directory('${folder.root.path}/pdf')
          .listSync()
          .whereType<File>()
          .single;
      final cropLine = logger.lines.where((l) => l.contains('Page crop:'));
      report(
        '$pages pages, $label: shots ${capture.elapsedMilliseconds} ms; '
        'after Done: store $saveMs ms, reading+PDF ${totalMs - saveMs} ms, '
        'total $totalMs ms; PDF ${pdfFile.lengthSync()} bytes; memory start '
        '${mb(rssStart)}, end ${mb(rssEnd)}, peak ${mb(rssPeak)}; '
        '${cropLine.isEmpty ? 'no crop line' : cropLine.first}',
      );

      await tester.ensureVisible(find.byKey(ScanKeys.discard));
      await tester.tap(find.byKey(ScanKeys.discard));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ScanKeys.discardConfirm));
      await pumpUntil(tester, find.text('The scan was deleted.'));
    }, timeout: const Timeout(Duration(minutes: 14)));
  }
}

/// Gives the invented photos, one after the other, as the shots of the camera.
class _SceneCamera extends FakeCameraService {
  _SceneCamera(this.dir, this.images) {
    // Encode once: every shot is a copy of the same bytes.
    for (final image in images) {
      _encoded.add(img.encodeJpg(image, quality: 92));
    }
  }

  final Directory dir;
  final List<img.Image> images;
  final List<List<int>> _encoded = [];
  final List<File> shots = [];
  var _n = 0;

  @override
  Future<CapturedPage> capture({required int order}) async {
    final file = File('${dir.path}/shot_$_n.jpg')
      ..writeAsBytesSync(_encoded[_n % _encoded.length]);
    _n++;
    shots.add(file);
    return CapturedPage(path: file.path, order: order);
  }
}
