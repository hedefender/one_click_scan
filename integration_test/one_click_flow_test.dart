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
import 'package:one_click_scan/domain/mail/mail_provider.dart';
import 'package:one_click_scan/domain/ocr/ocr_language_pack_registry.dart';
import 'package:one_click_scan/domain/entities/pdf_page_input.dart';
import 'package:one_click_scan/domain/ports/mail_credential_store.dart';
import 'package:one_click_scan/domain/ports/pdf_builder.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/scan/scan_keys.dart';
import 'package:one_click_scan/services/gallery/media_store_gallery_service.dart';
import 'package:one_click_scan/services/mail/android_mail_channels.dart';
import 'package:one_click_scan/services/mail/mail_services.dart';
import 'package:one_click_scan/services/mail/secure_mail_credential_store.dart';
import 'package:one_click_scan/services/mail/smtp_mail_sender.dart';
import 'package:one_click_scan/services/ocr/ocr_services.dart';
import 'package:one_click_scan/services/pdf/pdf_services.dart';
import 'package:path_provider/path_provider.dart';

import '../test/support/fakes.dart';
import '../test/support/mail_fakes.dart';
import '../test/support/pdf_fakes.dart';
import '../test/support/scan_fakes.dart';
import 'support/directory_scan_file_store.dart';
import 'support/synthetic_pages.dart';

/// Phase 5 on the Claude Code emulator: One Click and the preview with Discard,
/// with the real OCR models, the real PDF writer, the real SMTP sender against
/// the test server on the PC (the `testLocal` provider, as in Phase 4), the
/// real Gallery (MediaStore) and a real directory as the user's folder. Invented
/// pages and accounts only; no real Internet. Run it with
///   tool/run_mail_integration_test.sh `<emulator-id>` integration_test/one_click_flow_test.dart
/// Times are printed as `ONECLICKIT ...` lines. None is asserted: an x86
/// emulator says nothing about the speed of a phone.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const smtpPort = int.fromEnvironment('MAIL_SMTP_PORT');
  const controlPort = int.fromEnvironment('MAIL_CONTROL_PORT');
  const host = '10.0.2.2'; // the PC, seen from the emulator
  const account = 'user@example.test';
  const password = 'test-password';
  const galleryPrefix = 'scan_2026-10-21_';

  late Directory cache;
  late Directory work;
  late PdfServices pdf;
  late OcrServices ocr;
  late img.Image greekPage;
  late DirectoryScanFileStore folder;
  final logger = CapturingLogger();

  void report(String message) {
    // ignore: avoid_print
    print('ONECLICKIT $message');
  }

  Future<String> control(String method, String path) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('http://$host:$controlPort$path'),
      );
      final response = await request.close();
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  Future<List<Map<String, dynamic>>> receivedMails() async {
    final body = await control('GET', '/mails');
    return (jsonDecode(body) as List).cast<Map<String, dynamic>>();
  }

  Future<void> serverMode(String mode) => control('POST', '/mode/$mode');

  MailServices realMail() {
    final provider = testLocalProvider(host: host, port: smtpPort);
    return MailServices(
      sender: SmtpMailSender(
        logger: logger,
        socketTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 90),
      ),
      credentials: SecureMailCredentialStore(
        store: const PluginSecureStringStore(),
        logger: logger,
      ),
      attachments: AndroidAttachmentSource(
        directory: Directory('${cache.path}/mail_work'),
      ),
      appFinder: AndroidMailAppFinder(),
      links: AndroidLinkOpener(),
      sharer: AndroidDraftSharer(),
      providers: MailProviderRegistry({
        MailProviderId.gmail: provider,
        MailProviderId.outlook: provider,
        MailProviderId.yahoo: provider,
      }),
    );
  }

  /// The scan copies in the phone Gallery that this test made (the app owns
  /// them, so it can see them by their path on Android 11 and newer).
  List<String> galleryFiles() {
    try {
      final dir = Directory('/storage/emulated/0/Pictures');
      if (!dir.existsSync()) return <String>[];
      return [
        for (final entry in dir.listSync())
          if (entry is File &&
              entry.uri.pathSegments.last.startsWith(galleryPrefix))
            entry.uri.pathSegments.last,
      ]..sort();
    } on FileSystemException {
      fail('The Gallery folder could not be listed by the app');
    }
  }

  List<String> pictures() =>
      folder.files('pictures').where((n) => n.endsWith('.jpg')).toList();

  Future<void> startApp(
    WidgetTester tester, {
    required ScanFlowMode? mode,
    int pagesInScan = 1,
    Duration pdfDelay = Duration.zero,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final shots = Directory('${work.path}/shots')..createSync(recursive: true);
    folder = DirectoryScanFileStore(
      Directory('${work.path}/user_folder')..createSync(recursive: true),
    );
    final container = await buildTestContainer(
      camera: _SyntheticCamera(shots, [greekPage]),
      scanFileStore: folder,
      scanTempStore: FakeScanTempStore(),
      gallery: MediaStoreGalleryService(),
      ocr: ocr,
      pdf: PdfServices(
        builder: pdfDelay == Duration.zero
            ? pdf.builder
            : _SlowPdfBuilder(pdf.builder, pdfDelay),
        opener: FakeOpenPdf(),
      ),
      mail: realMail(),
    );
    final repository = container<SettingsRepository>();
    await repository.save(
      (await repository.load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        ocrPackId: OcrPackIds.greek,
        mailProvider: MailProviderId.gmail,
        senderAccount: account,
        saveToGallery: true,
        scanFlowMode: mode,
      ),
    );
    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeKeys.scanAndSend));
    await tester.pumpAndSettle();
  }

  Future<void> pumpUntil(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 150),
  }) async {
    final end = DateTime.now().add(timeout);
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) fail('Timed out waiting for $finder');
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  const sentText = 'The message was sent from the e-mail server.';

  setUpAll(() async {
    cache = await getTemporaryDirectory();
    work = Directory('${cache.path}/one_click_it')..createSync(recursive: true);
    ocr = await createPlatformOcrServices(
      registry: OcrLanguagePackRegistry.standard,
      logger: const DebugAppLogger(),
    );
    pdf = await createPlatformPdfServices(logger: const DebugAppLogger());
    greekPage = await renderDocument(greekReceipt.lines);
    expect(smtpPort, isNonZero, reason: 'run it with the script of tool/');
  });

  tearDownAll(() async {
    await ocr.engine.dispose();
    await ocr.workStore.purgeAll();
    await pdf.builder.purgeAll();
    if (work.existsSync()) work.deleteSync(recursive: true);
    await SecureMailCredentialStore(
      store: const PluginSecureStringStore(),
      logger: logger,
    ).delete();
  });

  setUp(() async {
    await control('POST', '/reset');
    await SecureMailCredentialStore(
      store: const PluginSecureStringStore(),
      logger: logger,
    ).write(
      const StoredMailSecret(
        provider: MailProviderId.gmail,
        accountEmail: account,
        secret: password,
      ),
    );
  });

  tearDown(() {
    for (final name in ['user_folder', 'shots']) {
      final dir = Directory('${work.path}/$name');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  testWidgets('One Click, single page: one tap stores, reads, makes the PDF '
      'and sends it', (tester) async {
    await startApp(tester, mode: ScanFlowMode.oneClick);
    final galleryBefore = galleryFiles();
    final clock = Stopwatch()..start();

    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pump();
    await pumpUntil(tester, find.text(sentText));
    clock.stop();

    final storedPdf = File('${folder.root.path}/pdf/2026-10-21_19-05-12.pdf');
    expect(storedPdf.existsSync(), isTrue);
    expect(pictures(), ['2026-10-21_19-05-12_1.jpg']);
    expect(galleryFiles().length, galleryBefore.length + 1);
    final received = (await receivedMails()).single;
    expect(received['subject'], 'One Click Scan - 2026-10-21_19-05-12');
    final attachment = (received['attachments'] as List).single as Map;
    expect(attachment['name'], '2026-10-21_19-05-12.pdf');
    expect(
      attachment['sha256'],
      sha256.convert(storedPdf.readAsBytesSync()).toString(),
    );
    expect(find.byKey(ScanKeys.discard), findsNothing);
    report(
      'one click, 1 page: ${clock.elapsedMilliseconds} ms from the shot to '
      '"sent", PDF ${storedPdf.lengthSync()} bytes, attachment identical',
    );
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('One Click, three pages: one PDF and one message', (
    tester,
  ) async {
    await startApp(tester, mode: ScanFlowMode.oneClick);
    await tester.tap(find.text('Multi page'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pump(const Duration(milliseconds: 500));
      await pumpUntil(
        tester,
        find.byKey(ScanKeys.capture),
        timeout: const Duration(seconds: 30),
      );
    }
    expect(await receivedMails(), isEmpty);
    final clock = Stopwatch()..start();

    await tester.tap(find.byKey(ScanKeys.done));
    await tester.pump();
    await pumpUntil(tester, find.text(sentText));
    clock.stop();

    expect(pictures(), hasLength(3));
    final mails = await receivedMails();
    expect(mails, hasLength(1));
    final attachment = (mails.single['attachments'] as List).single as Map;
    expect(attachment['name'], '2026-10-21_19-05-12.pdf');
    report(
      'one click, 3 pages: ${clock.elapsedMilliseconds} ms from Done to sent',
    );
  }, timeout: const Timeout(Duration(minutes: 6)));

  testWidgets('One Click, the server is not there: "Not sent", everything is '
      'stored, and Try again works once it is back', (tester) async {
    await startApp(tester, mode: ScanFlowMode.oneClick);
    await serverMode('hang');

    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pump();
    await pumpUntil(
      tester,
      find.byKey(ScanKeys.flowNotSent),
      timeout: const Duration(seconds: 150),
    );

    expect(find.text('Not sent'), findsOneWidget);
    expect(find.byKey(ScanKeys.mailRetry), findsOneWidget);
    expect(pictures(), hasLength(1));
    expect(folder.files('pdf'), ['2026-10-21_19-05-12.pdf']);
    expect(await receivedMails(), isEmpty);

    await serverMode('accept');
    await tester.ensureVisible(find.byKey(ScanKeys.mailRetry));
    await tester.tap(find.byKey(ScanKeys.mailRetry));
    await pumpUntil(
      tester,
      find.text(sentText),
      timeout: const Duration(seconds: 60),
    );
    expect(await receivedMails(), hasLength(1));
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('preview, Send: the pages are shown first, then the message '
      'goes', (tester) async {
    await startApp(tester, mode: ScanFlowMode.preview);

    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pump();
    await pumpUntil(tester, find.byKey(ScanKeys.mailSend));

    expect(find.byKey(ScanKeys.discard), findsOneWidget);
    expect(await receivedMails(), isEmpty);
    await tester.ensureVisible(find.byKey(ScanKeys.mailSend));
    await tester.tap(find.byKey(ScanKeys.mailSend));
    await pumpUntil(tester, find.text(sentText));
    expect(await receivedMails(), hasLength(1));
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('preview, Discard: pictures, PDF and Gallery copy are gone and '
      'nothing was sent', (tester) async {
    await startApp(tester, mode: ScanFlowMode.preview);
    final galleryBefore = galleryFiles();

    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pump();
    await pumpUntil(tester, find.byKey(ScanKeys.discard));

    // Everything exists before the decision.
    expect(pictures(), hasLength(1));
    expect(folder.files('pdf'), hasLength(1));
    expect(galleryFiles().length, galleryBefore.length + 1);

    await tester.ensureVisible(find.byKey(ScanKeys.discard));
    await tester.tap(find.byKey(ScanKeys.discard));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ScanKeys.discardConfirm));
    await pumpUntil(tester, find.text('The scan was deleted.'));

    expect(pictures(), isEmpty);
    expect(folder.files('pdf'), isEmpty);
    expect(galleryFiles(), galleryBefore);
    expect(await receivedMails(), isEmpty);
    report(
      'discard: ${pictures().length} pictures, ${folder.files('pdf').length} PDFs, '
      '${galleryFiles().length - galleryBefore.length} new Gallery copies left',
    );
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('Phase 5.1: Cancel while the text is read (many pages): the '
      'pictures stay, no PDF, no message', (tester) async {
    await startApp(tester, mode: ScanFlowMode.oneClick);
    await tester.tap(find.text('Multi page'));
    await tester.pumpAndSettle();
    // Shoot faster than the OCR reads, so the reading is still running.
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pump(const Duration(milliseconds: 150));
    }
    await pumpUntil(tester, find.byKey(ScanKeys.done));
    await tester.tap(find.byKey(ScanKeys.done));
    await tester.pump();
    await pumpUntil(tester, find.byKey(ScanKeys.flowCancel));

    await tester.tap(find.byKey(ScanKeys.flowCancel));
    await pumpUntil(tester, find.byKey(ScanKeys.flowCancelled));

    expect(pictures(), hasLength(8));
    expect(folder.files('pdf'), isEmpty);
    expect(await receivedMails(), isEmpty);
    expect(find.byKey(ScanKeys.mailSend), findsNothing);
    report('cancel while reading: 8 pictures stay, 0 PDFs, 0 messages');
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('Phase 5.1: Cancel while the PDF is made: no PDF is left, even '
      'when the writer finishes later', (tester) async {
    await startApp(
      tester,
      mode: ScanFlowMode.oneClick,
      pdfDelay: const Duration(seconds: 6),
    );

    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pump();
    await pumpUntil(tester, find.byKey(ScanKeys.pdfStatus));
    // The PDF stage shows its Cancel button.
    await pumpUntil(tester, find.text('Creating the PDF…'));
    await tester.tap(find.byKey(ScanKeys.flowCancel));
    await pumpUntil(tester, find.byKey(ScanKeys.flowCancelled));
    expect(find.byKey(ScanKeys.mailSend), findsNothing);

    // Give the (delayed) writer time to finish; its file must be deleted again.
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(pictures(), hasLength(1));
    expect(folder.files('pdf'), isEmpty);
    final pdfDir = Directory('${work.path}/user_folder/pdf');
    expect(
      pdfDir.existsSync()
          ? pdfDir.listSync().where(
              (e) => e.path.endsWith('.tmp') || e.path.endsWith('.pdf'),
            )
          : const <FileSystemEntity>[],
      isEmpty,
    );
    expect(await receivedMails(), isEmpty);
    report('cancel while the PDF is made: 1 picture stays, 0 PDFs, 0 .tmp');
  }, timeout: const Timeout(Duration(minutes: 4)));

  testWidgets('Phase 5.1: after a successful send the screen goes home by '
      'itself, and a touch stops that', (tester) async {
    await startApp(tester, mode: ScanFlowMode.oneClick);
    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pump();
    await pumpUntil(tester, find.text(sentText));
    expect(find.byKey(ScanKeys.autoReturn), findsOneWidget);

    final clock = Stopwatch()..start();
    await pumpUntil(
      tester,
      find.byKey(HomeKeys.scanAndSend),
      timeout: const Duration(seconds: 25),
    );
    clock.stop();
    expect(clock.elapsed, greaterThan(const Duration(seconds: 6)));
    report('auto return: home after ${clock.elapsedMilliseconds} ms (of 10 s)');

    // A second scan: a touch keeps the user on the result screen.
    await tester.tap(find.byKey(HomeKeys.scanAndSend));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pump();
    await pumpUntil(tester, find.byKey(ScanKeys.autoReturn));
    await tester.tap(find.byKey(ScanKeys.resultSummary));
    await tester.pump();
    final end = DateTime.now().add(const Duration(seconds: 13));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byKey(ScanKeys.resultSummary), findsOneWidget);
    expect(find.byKey(ScanKeys.autoReturn), findsNothing);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('nothing of the user is in the logs of all of the above', () {
    for (final text in [password, account, 'One Click Scan - 2026']) {
      expect(logger.all, isNot(contains(text)), reason: text);
    }
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

/// The real PDF writer, started late: it makes the PDF stage long enough for a
/// test to press Cancel in it, and the writer still finishes afterwards.
class _SlowPdfBuilder implements PdfBuilder {
  _SlowPdfBuilder(this._inner, this._delay);

  final PdfBuilder _inner;
  final Duration _delay;

  @override
  Future<BuiltPdf> build(List<PdfPageInput> pages) async {
    await Future<void>.delayed(_delay);
    return _inner.build(pages);
  }

  @override
  Future<void> discard(String path) => _inner.discard(path);

  @override
  Future<void> purgeAll() => _inner.purgeAll();
}
