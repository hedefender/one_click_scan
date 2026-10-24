import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/core/logging/app_logger.dart';
import 'package:one_click_scan/domain/entities/captured_page.dart';
import 'package:one_click_scan/domain/ocr/ocr_language_pack_registry.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/ocr/ocr_keys.dart';
import 'package:one_click_scan/features/scan/scan_keys.dart';
import 'package:one_click_scan/services/ocr/ocr_services.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/fakes.dart';
import '../test/support/scan_fakes.dart';
import 'support/synthetic_pages.dart';

/// The whole app on the emulator with the REAL OCR (models, isolate, Kotlin
/// decode) and a camera that hands out invented pages: scan, Done, open the
/// OCR check screen, read the text. Run on the Claude Code emulator only:
///   tool/run_integration_test.sh `<emulator-id>` integration_test/ocr_flow_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// A camera whose shots are real JPEG files of invented pages.
  Future<FakeCameraService> syntheticCamera(
    Directory dir,
    List<img.Image> pages,
  ) async {
    return _SyntheticCamera(dir, pages);
  }

  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final end = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        fail('Timed out waiting for $finder');
      }
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('Multi Page scan with the real OCR: two pages, two languages', (
    tester,
  ) async {
    final cache = await getTemporaryDirectory();
    final dir = Directory('${cache.path}/ocr_flow')
      ..createSync(recursive: true);
    final greek = await renderDocument(greekReceipt.lines);
    final latin = await renderDocument(latinAccents.lines);

    final ocr = await createPlatformOcrServices(
      registry: OcrLanguagePackRegistry.standard,
      logger: const DebugAppLogger(),
    );
    final container = await buildTestContainer(
      camera: await syntheticCamera(dir, [greek, latin]),
      scanFileStore: FakeScanFileStore(),
      scanTempStore: FakeScanTempStore(),
      ocr: ocr,
    );
    final repository = container<SettingsRepository>();
    await repository.save(
      (await repository.load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        ocrPackId: OcrPackIds.greek,
      ),
    );

    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeKeys.scanAndSend));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Multi page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ScanKeys.done));
    await tester.pumpAndSettle();
    expect(find.text('Scan saved'), findsOneWidget);

    await tester.tap(find.byKey(ScanKeys.resultOcr));
    await tester.pumpAndSettle();
    expect(find.byKey(OcrKeys.pageLabel), findsOneWidget);

    // Page 1 (Greek receipt): the summary appears when the page is read.
    await pumpUntil(tester, find.byKey(OcrKeys.summary));
    expect(find.textContaining('45,90'), findsWidgets);
    expect(find.textContaining('ΠΑΡΑΔΕΙΓΜΑ'), findsWidgets);
    expect(
      find.textContaining('Language pack: Greek + English'),
      findsOneWidget,
    );
    expect(find.textContaining('Capture: 1240 x'), findsOneWidget);
    // No spinner at any time on this screen.
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Page 2 is read with the same (Greek) pack: it still finds the English
    // and the numbers, which is exactly why the pack choice is the user's.
    await tester.tap(find.byKey(OcrKeys.nextPage));
    await tester.pumpAndSettle();
    await pumpUntil(tester, find.byKey(OcrKeys.summary));
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(find.textContaining('20260312'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ScanKeys.resultBack));
    await tester.pumpAndSettle();
    expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);

    await ocr.engine.dispose();
    dir.deleteSync(recursive: true);
  });
}

class _SyntheticCamera extends FakeCameraService {
  _SyntheticCamera(this.dir, this.pages);

  final Directory dir;
  final List<img.Image> pages;
  var _n = 0;

  @override
  Future<CapturedPage> capture({required int order}) async {
    final page = pages[_n % pages.length];
    final file = writeJpeg('${dir.path}/shot_${_n++}.jpg', page);
    return CapturedPage(path: file.path, order: order);
  }
}
