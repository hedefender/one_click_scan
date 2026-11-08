import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/core/logging/app_logger.dart';
import 'package:one_click_scan/domain/entities/captured_page.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/scan_flow_mode.dart';
import 'package:one_click_scan/domain/mail/mail_provider.dart';
import 'package:one_click_scan/domain/mail/mail_size_policy.dart';
import 'package:one_click_scan/domain/ocr/ocr_language_pack_registry.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/scan/scan_cubit.dart';
import 'package:one_click_scan/features/scan/scan_keys.dart';
import 'package:one_click_scan/services/mail/mail_services.dart';
import 'package:one_click_scan/services/ocr/ocr_services.dart';
import 'package:one_click_scan/services/pdf/pdf_services.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/fakes.dart';
import '../test/support/mail_fakes.dart';
import '../test/support/pdf_fakes.dart';
import '../test/support/scan_fakes.dart';
import 'support/directory_scan_file_store.dart';
import 'support/synthetic_pages.dart';

/// Phase 6.3 (ADR-032) on the Claude Code emulator: a Multi Page scan with
/// synthetic pages of different content, taken up to the limit, with the real
/// OCR and crop queue (so the sizes the budget uses are the real working
/// copies), the real PDF writer and a real directory as the user's folder.
///
///  * the shot is blocked at the limit, the screen says why, and the PDF made
///    after "Done" stays under the limit of the provider;
///  * the estimate of the cubit just before "Done" is compared with the real
///    PDF (the numbers are printed as `LIMITIT ...` and go to
///    `PHASE_6_3_VALIDATION.md`).
///
/// The camera is a fake that hands out synthetic photos (never the webcam).
/// NOT tested here: real phone photos, so the real sizes per page and the real
/// margin wait for the phone. Run on the Claude Code emulator only:
///   tool/run_integration_test.sh `<emulator-id>` integration_test/page_limit_flow_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const account = 'user@example.test';

  late Directory work;
  late OcrServices ocr;
  late PdfServices pdf;
  late DirectoryScanFileStore folder;
  late List<List<int>> kinds;

  void report(String message) {
    // ignore: avoid_print
    print('LIMITIT $message');
  }

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

  setUpAll(() async {
    final cache = await getTemporaryDirectory();
    work = Directory('${cache.path}/page_limit_it')
      ..createSync(recursive: true);
    ocr = await createPlatformOcrServices(
      registry: OcrLanguagePackRegistry.standard,
      logger: const DebugAppLogger(),
    );
    pdf = await createPlatformPdfServices(logger: const DebugAppLogger());

    // Three kinds of photo, 1536 x 2048 on a grey table: an invented receipt
    // (text, much white), a page with texture (a photo of something) and a
    // nearly empty page.
    final flat = await renderDocument(greekReceipt.lines);
    img.Image onTable(img.Image page) {
      final photo = img.Image(width: 1536, height: 2048, numChannels: 3);
      img.fill(photo, color: img.ColorRgb8(238, 238, 238));
      img.compositeImage(
        photo,
        img.copyResize(page, width: 1200),
        dstX: 168,
        dstY: 200,
      );
      return photo;
    }

    final receipt = onTable(flat);
    final random = Random(3);
    final textured = img.Image(width: 1200, height: 1600, numChannels: 3);
    for (final pixel in textured) {
      final v = (140 + 50 * sin(pixel.x / 25) + random.nextInt(70)).round();
      pixel
        ..r = v
        ..g = (v * 0.92).round()
        ..b = (v * 0.85).round();
    }
    final empty = onTable(
      img.Image(width: 1200, height: 1600, numChannels: 3)
        ..clear(img.ColorRgb8(250, 250, 250)),
    );
    kinds = [
      img.encodeJpg(receipt, quality: 92),
      img.encodeJpg(onTable(textured), quality: 92),
      img.encodeJpg(empty, quality: 92),
    ];
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

  /// A provider that takes [attachmentBytes] of file, so a few pages fill it.
  MailProviderRegistry providerFor(int attachmentBytes) {
    final message =
        (attachmentBytes * MailSizePolicy.encodingFactor).ceil() +
        MailSizePolicy.headroomBytes;
    return MailProviderRegistry({
      MailProviderId.gmail: MailProvider(
        id: 'tiny',
        smtp: const SmtpEndpoint(
          host: 'localhost',
          port: 1,
          security: SmtpSecurity.plain,
        ),
        authKinds: const {MailAuthKind.appPassword},
        appPasswordSupport: AppPasswordSupport.supported,
        maxMessageBytes: message,
      ),
      MailProviderId.outlook: MailProviderRegistry.standard.resolve(
        MailProviderId.outlook,
      ),
      MailProviderId.yahoo: MailProviderRegistry.standard.resolve(
        MailProviderId.yahoo,
      ),
    });
  }

  Future<ScanCubit> startApp(
    WidgetTester tester, {
    required int limitBytes,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    folder = DirectoryScanFileStore(
      Directory('${work.path}/folder')..createSync(recursive: true),
    );
    final rig = MailTestRig()..storePassword(account: account);
    final camera = _ShotCamera(
      Directory('${work.path}/shots_${DateTime.now().microsecondsSinceEpoch}')
        ..createSync(recursive: true),
      kinds,
    );
    final container = await buildTestContainer(
      camera: camera,
      scanFileStore: folder,
      scanTempStore: FakeScanTempStore(),
      gallery: FakeGalleryService(),
      ocr: ocr,
      pdf: PdfServices(builder: pdf.builder, opener: FakeOpenPdf()),
      mail: MailServices(
        sender: rig.sender,
        credentials: rig.credentials,
        attachments: rig.attachments,
        sharer: rig.sharer,
        appFinder: rig.appFinder,
        links: rig.links,
        providers: providerFor(limitBytes),
      ),
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
        scanFlowMode: ScanFlowMode.preview,
      ),
    );
    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeKeys.scanAndSend));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Multi page'));
    await tester.pumpAndSettle();
    return tester.element(find.byKey(ScanKeys.capture)).read<ScanCubit>();
  }

  Future<void> shoot(WidgetTester tester) async {
    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pump(const Duration(milliseconds: 300));
    // The shot ends (the button is idle again) while the pages are prepared
    // in the background; the sizes arrive after the crop of each page.
    await pumpUntil(tester, find.byKey(ScanKeys.capture));
    await tester.pump(const Duration(seconds: 3));
  }

  File pdfFile() =>
      Directory('${folder.root.path}/pdf')
          .listSync()
          .whereType<File>()
          .firstWhere((f) => f.path.endsWith('.pdf'));

  testWidgets('shots stop at the limit; the PDF after "Done" stays under it', (
    tester,
  ) async {
    const limit = 3 * 1024 * 1024; // the provider takes a 3 MB PDF
    final cubit = await startApp(tester, limitBytes: limit);

    var shots = 0;
    while (!cubit.state.pageLimitReached && shots < 25) {
      await shoot(tester);
      shots++;
      final b = cubit.state.budget!;
      report(
        'shot $shots: counter ${b.showCounter ? '$shots/${b.maxPages}' : '$shots'}, '
        'estimate ${(b.estimatedBytes / 1024).round()} KB of '
        '${(b.limitBytes / 1024).round()} KB',
      );
    }
    final budget = cubit.state.budget!;
    expect(budget.reached, isTrue, reason: 'the limit was reached');
    expect(shots, lessThan(25), reason: 'the size limit came before 25');
    expect(find.byKey(ScanKeys.pageLimitReached), findsOneWidget);
    expect(cubit.state.canCapture, isFalse);
    final before = shots;
    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pumpAndSettle();
    expect(cubit.state.pages.length, before, reason: 'no shot at the limit');

    final estimated = budget.estimatedBytes;
    await tester.tap(find.byKey(ScanKeys.done));
    await pumpUntil(tester, find.byKey(ScanKeys.pdfDetails));
    final real = pdfFile().lengthSync();
    final error = (estimated - real) / real;
    report(
      'at the limit: $before pages, estimate ${(estimated / 1024).round()} KB, '
      'real PDF ${(real / 1024).round()} KB, error '
      '${(error * 100).toStringAsFixed(1)} %, limit ${(limit / 1024).round()} KB',
    );
    expect(real, lessThanOrEqualTo(limit), reason: 'the PDF fits the provider');
  }, timeout: const Timeout(Duration(minutes: 20)));

  testWidgets('estimate against the real PDF for a scan of different pages', (
    tester,
  ) async {
    // Gmail's real limit, pages taken until the 6th (not to the limit).
    final cubit = await startApp(
      tester,
      limitBytes: MailSizePolicy.maxAttachmentBytes(
        MailProviderRegistry.standard.resolve(MailProviderId.gmail),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await shoot(tester);
    }
    final budget = cubit.state.budget!;
    expect(budget.pageCount, 6);
    expect(budget.showCounter, isTrue, reason: 'n/XX from page 5');
    expect(find.textContaining('Pages: 6/'), findsOneWidget);
    final estimated = budget.estimatedBytes;

    await tester.tap(find.byKey(ScanKeys.done));
    await pumpUntil(tester, find.byKey(ScanKeys.pdfDetails));
    final real = pdfFile().lengthSync();
    final error = (estimated - real) / real;
    report(
      '6 mixed pages: XX=${budget.maxPages}, estimate '
      '${(estimated / 1024).round()} KB, real PDF ${(real / 1024).round()} KB, '
      'error ${(error * 100).toStringAsFixed(1)} %',
    );
    // The sum of the measured pictures plus the overheads is close to the file.
    expect(error.abs(), lessThan(0.05));
  }, timeout: const Timeout(Duration(minutes: 20)));
}

class _ShotCamera extends FakeCameraService {
  _ShotCamera(this.dir, this.images);

  final Directory dir;
  final List<List<int>> images;
  var _n = 0;

  @override
  Future<CapturedPage> capture({required int order}) async {
    final file = File('${dir.path}/shot_$_n.jpg')
      ..writeAsBytesSync(images[_n % images.length]);
    _n++;
    return CapturedPage(path: file.path, order: order);
  }
}
