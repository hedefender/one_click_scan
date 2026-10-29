import 'dart:io';

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
import 'package:one_click_scan/services/gallery/media_store_gallery_service.dart';
import 'package:one_click_scan/services/ocr/ocr_services.dart';
import 'package:one_click_scan/services/pdf/pdf_services.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/fakes.dart';
import '../test/support/pdf_fakes.dart';
import '../test/support/scan_fakes.dart';
import 'support/directory_scan_file_store.dart';
import 'support/synthetic_pages.dart';

/// Phase 5.1: measures (changes nothing) how long a scan of 5 and of 21 invented
/// pages takes after "Done" (store, read, PDF) and how much memory the app
/// holds at the end, with the real OCR, the real PDF writer, the real Gallery
/// copy and a real directory as the folder. The shots are taken one after the
/// other without waiting for the reading, which is the worst case for the
/// time after "Done". The numbers feed the decision of Phase 6 (processing
/// during the capture). Printed as `MEASURE ...` lines, nothing is asserted:
/// an x86 emulator says nothing about the speed of a phone. Run on the Claude
/// Code emulator only:
///   tool/run_integration_test.sh `<emulator-id>` integration_test/processing_measure_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory work;
  late PdfServices pdf;
  late OcrServices ocr;
  late img.Image page;

  void report(String message) {
    // ignore: avoid_print
    print('MEASURE $message');
  }

  String mb(int bytes) => '${(bytes / (1024 * 1024)).round()} MB';

  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(minutes: 8),
  }) async {
    final end = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) fail('Timed out waiting for $finder');
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  setUpAll(() async {
    final cache = await getTemporaryDirectory();
    work = Directory('${cache.path}/measure_it')..createSync(recursive: true);
    ocr = await createPlatformOcrServices(
      registry: OcrLanguagePackRegistry.standard,
      logger: const DebugAppLogger(),
    );
    pdf = await createPlatformPdfServices(logger: const DebugAppLogger());
    page = await renderDocument(greekReceipt.lines);
  });

  tearDownAll(() async {
    await ocr.engine.dispose();
    await ocr.workStore.purgeAll();
    await pdf.builder.purgeAll();
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  for (final pages in [5, 21]) {
    testWidgets('measure: $pages pages', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final shots = Directory('${work.path}/shots_$pages')
        ..createSync(recursive: true);
      final folder = DirectoryScanFileStore(
        Directory('${work.path}/folder_$pages')..createSync(recursive: true),
      );
      final container = await buildTestContainer(
        camera: _SyntheticCamera(shots, page),
        scanFileStore: folder,
        scanTempStore: FakeScanTempStore(),
        gallery: MediaStoreGalleryService(),
        ocr: ocr,
        pdf: PdfServices(builder: pdf.builder, opener: FakeOpenPdf()),
      );
      final repository = container<SettingsRepository>();
      await repository.save(
        (await repository.load()).copyWith(
          firstRunCompleted: true,
          storageFolder: testFolder,
          ocrPackId: OcrPackIds.greek,
          mailProvider: MailProviderId.gmail,
          senderAccount: 'user@example.test',
          saveToGallery: true,
          scanFlowMode: ScanFlowMode.preview,
        ),
      );
      await tester.pumpWidget(OneClickScanApp(container: container));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(HomeKeys.scanAndSend));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Multi page'));
      await tester.pumpAndSettle();
      final rssStart = ProcessInfo.currentRss;

      final capture = Stopwatch()..start();
      for (var i = 0; i < pages; i++) {
        await tester.tap(find.byKey(ScanKeys.capture));
        await tester.pump(const Duration(milliseconds: 100));
        await pumpUntil(tester, find.byKey(ScanKeys.capture));
      }
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
      report(
        '$pages pages: shots (with the reading running behind) '
        '${capture.elapsedMilliseconds} ms; after Done: store+Gallery '
        '$saveMs ms, reading+PDF ${totalMs - saveMs} ms, total $totalMs ms; '
        'PDF ${pdfFile.lengthSync()} bytes; memory start ${mb(rssStart)}, '
        'end ${mb(rssEnd)}, peak ${mb(rssPeak)}',
      );

      // Clean up: the copies in the Gallery of the emulator.
      await tester.ensureVisible(find.byKey(ScanKeys.discard));
      await tester.tap(find.byKey(ScanKeys.discard));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ScanKeys.discardConfirm));
      await pumpUntil(tester, find.text('The scan was deleted.'));
    }, timeout: const Timeout(Duration(minutes: 12)));
  }
}

class _SyntheticCamera extends FakeCameraService {
  _SyntheticCamera(this.dir, this.page);

  final Directory dir;
  final img.Image page;
  var _n = 0;

  @override
  Future<CapturedPage> capture({required int order}) async {
    final file = writeJpeg('${dir.path}/shot_${_n++}.jpg', page);
    return CapturedPage(path: file.path, order: order);
  }
}
