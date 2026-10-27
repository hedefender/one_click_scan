import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/core/logging/app_logger.dart';
import 'package:one_click_scan/domain/entities/app_language.dart';
import 'package:one_click_scan/domain/entities/app_settings.dart';
import 'package:one_click_scan/domain/entities/captured_page.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/pdf_page_input.dart';
import 'package:one_click_scan/domain/mail/mail_cancellation.dart';
import 'package:one_click_scan/domain/mail/mail_outcome.dart';
import 'package:one_click_scan/domain/mail/mail_provider.dart';
import 'package:one_click_scan/domain/mail/share_route.dart';
import 'package:one_click_scan/domain/ocr/ocr_language_pack_registry.dart';
import 'package:one_click_scan/domain/ports/mail_credential_store.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/domain/usecases/send_scan_pdf.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/scan/scan_keys.dart';
import 'package:one_click_scan/features/settings/settings_keys.dart';
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

/// Phase 4 on the Claude Code emulator: the real mail layer (the `mailer`
/// package in its isolate, the Android Keystore, the native file copy, the
/// share intent) against a test SMTP server that runs on the PC and that the
/// emulator reaches as 10.0.2.2. Run it with
///   tool/run_mail_integration_test.sh `<emulator-id>`
/// which starts the server, passes its ports and stops it. Invented accounts
/// and passwords only (`user@example.test` / `test-password`); no real account
/// and no real Internet.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const smtpPort = int.fromEnvironment('MAIL_SMTP_PORT');
  const controlPort = int.fromEnvironment('MAIL_CONTROL_PORT');
  const host = '10.0.2.2'; // the PC, seen from the emulator
  const account = 'user@example.test';
  const password = 'test-password';

  late Directory cache;
  late Directory work;
  late PdfServices pdf;
  late OcrServices ocr;
  late img.Image greekPage;
  final logger = CapturingLogger();

  void report(String message) {
    // ignore: avoid_print
    print('MAILIT $message');
  }

  // --- The control interface of the server on the PC ----------------------

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

  MailProvider providerFor({int? port, int maxMessageBytes = 25000000}) {
    return testLocalProvider(
      host: host,
      port: port ?? smtpPort,
      maxMessageBytes: maxMessageBytes,
    );
  }

  MailProviderRegistry registryFor(MailProvider provider) {
    return MailProviderRegistry({
      MailProviderId.gmail: provider,
      MailProviderId.outlook: provider,
      MailProviderId.yahoo: provider,
    });
  }

  /// The mail services of the real app, with the registry that maps the
  /// provider to the server on the PC and short timeouts.
  MailServices realMail(MailProvider provider) {
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
      providers: registryFor(provider),
    );
  }

  /// A "stored PDF": a file with a PDF header and binary content, reachable
  /// by a `file:` URI (the real app has a `content:` URI of the SAF folder; the
  /// native copy takes both).
  StoredPdf makePdf(String name, {int size = 400000}) {
    final bytes = Uint8List.fromList(
      List<int>.generate(size, (i) => (i * 31 + i ~/ 97) % 256),
    );
    final file = File('${work.path}/$name')
      ..writeAsBytesSync([...ascii.encode('%PDF-1.7\n'), ...bytes]);
    return StoredPdf(
      fileName: name,
      uri: file.uri.toString(),
      pageCount: 1,
      textPageCount: 1,
      byteSize: file.lengthSync(),
    );
  }

  String hashOf(StoredPdf pdf) => sha256
      .convert(File(Uri.parse(pdf.uri).toFilePath()).readAsBytesSync())
      .toString();

  const settings = AppSettings(
    language: AppLanguage.en,
    mailProvider: MailProviderId.gmail,
    senderAccount: account,
  );

  SendScanPdf useCaseFor(MailServices mail) => SendScanPdf(
    sender: mail.sender,
    attachments: mail.attachments,
    credentials: mail.credentials,
    providers: mail.providers,
    logger: logger,
  );

  setUpAll(() async {
    cache = await getTemporaryDirectory();
    work = Directory('${cache.path}/mail_it')..createSync(recursive: true);
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

  // -------------------------------------------------------------------------
  group('the real mail layer against the server on the PC', () {
    test('a message arrives with the right subject, addresses and body, and '
        'the attachment is the file byte for byte', () async {
      final mail = realMail(providerFor());
      final stored = makePdf('2026-10-21_19-05-12.pdf');
      final clock = Stopwatch()..start();

      final outcome = await useCaseFor(mail)(settings: settings, pdf: stored);
      clock.stop();

      expect(outcome, isA<MailSent>());
      final mails = await receivedMails();
      expect(mails, hasLength(1));
      final received = mails.single;
      expect(received['subject'], 'One Click Scan - 2026-10-21_19-05-12');
      expect(received['from'], account);
      expect(received['to'], [account]);
      expect(
        (received['body'] as String).trim(),
        'Document scanned with One Click Scan.',
      );
      final attachments = (received['attachments'] as List)
          .cast<Map<String, dynamic>>();
      expect(attachments, hasLength(1));
      expect(attachments.single['name'], '2026-10-21_19-05-12.pdf');
      expect(attachments.single['size'], stored.byteSize);
      expect(attachments.single['sha256'], hashOf(stored));
      report(
        'send ${stored.byteSize} bytes: ${clock.elapsedMilliseconds} ms, '
        'message ${received['bytes']} bytes, attachment identical',
      );
      // The copy of the PDF in the cache is gone.
      final left = Directory('${cache.path}/mail_work');
      expect(
        left.existsSync() ? left.listSync() : <FileSystemEntity>[],
        isEmpty,
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a Greek body arrives intact', () async {
      final mail = realMail(providerFor());
      final stored = makePdf('2026-10-21_19-05-13.pdf', size: 1000);

      final outcome = await useCaseFor(mail)(
        settings: settings.copyWith(language: AppLanguage.el),
        pdf: stored,
      );

      expect(outcome, isA<MailSent>());
      final received = (await receivedMails()).single;
      expect(
        (received['body'] as String).trim(),
        'Σαρωμένο έγγραφο από το One Click Scan.',
      );
    });

    test('a wrong password is authFailed and nothing is delivered', () async {
      final mail = realMail(providerFor());
      await mail.credentials.write(
        const StoredMailSecret(
          provider: MailProviderId.gmail,
          accountEmail: account,
          secret: 'not-the-password',
        ),
      );

      final outcome = await useCaseFor(mail)(
        settings: settings,
        pdf: makePdf('a.pdf', size: 100),
      );

      expect(outcome, isA<MailAuthFailed>());
      expect(await receivedMails(), isEmpty);
    });

    test(
      'a server that is not there is a network outcome, with no crash',
      () async {
        final mail = realMail(providerFor(port: smtpPort + 100));
        final clock = Stopwatch()..start();

        final outcome = await useCaseFor(mail)(
          settings: settings,
          pdf: makePdf('a.pdf', size: 100),
        );

        expect(outcome, isA<MailNetworkError>());
        expect(clock.elapsed, lessThan(const Duration(seconds: 20)));
      },
    );

    test('a server that never answers ends with a timeout', () async {
      await serverMode('hang');
      final mail = realMail(providerFor());
      final clock = Stopwatch()..start();

      final outcome = await useCaseFor(mail)(
        settings: settings,
        pdf: makePdf('a.pdf', size: 100),
      );

      expect(outcome, isA<MailNetworkError>());
      expect(clock.elapsed, lessThan(const Duration(seconds: 25)));
      report('timeout after ${clock.elapsedMilliseconds} ms');
    });

    test('a send can be cancelled while the server is silent', () async {
      await serverMode('hang');
      final mail = realMail(providerFor());
      final cancellation = MailCancellation();

      final future = useCaseFor(mail)(
        settings: settings,
        pdf: makePdf('a.pdf', size: 100),
        cancellation: cancellation,
      );
      await Future<void>.delayed(const Duration(milliseconds: 800));
      cancellation.cancel();

      expect(await future, isA<MailCancelled>());
    });

    test('a PDF over the limit of the provider is refused before any '
        'connection', () async {
      final mail = realMail(providerFor(maxMessageBytes: 300000));
      final stored = makePdf('big.pdf', size: 400000);

      final outcome = await useCaseFor(mail)(settings: settings, pdf: stored);

      expect(outcome, isA<MailTooLarge>());
      expect(await receivedMails(), isEmpty);
    });

    test('a server that says 552 gives tooLarge', () async {
      await serverMode('tooLarge');
      final mail = realMail(providerFor());

      final outcome = await useCaseFor(mail)(
        settings: settings,
        pdf: makePdf('a.pdf', size: 5000),
      );

      expect(outcome, isA<MailTooLarge>());
      expect(await receivedMails(), isEmpty);
    });

    test(
      'after failures a new try works, from the same screen state',
      () async {
        final mail = realMail(providerFor());
        final stored = makePdf('2026-10-21_19-05-14.pdf', size: 50000);

        await serverMode('authFail');
        expect(
          await useCaseFor(mail)(settings: settings, pdf: stored),
          isA<MailAuthFailed>(),
        );
        await serverMode('tooLarge');
        expect(
          await useCaseFor(mail)(settings: settings, pdf: stored),
          isA<MailTooLarge>(),
        );
        await serverMode('accept');

        expect(
          await useCaseFor(mail)(settings: settings, pdf: stored),
          isA<MailSent>(),
        );
        expect(await receivedMails(), hasLength(1));
      },
    );

    test('the connection check signs in and sends nothing', () async {
      final mail = realMail(providerFor());
      final check = CheckMailConnection(
        sender: mail.sender,
        providers: mail.providers,
      );

      expect(
        await check(
          provider: MailProviderId.gmail,
          accountEmail: account,
          secret: password,
        ),
        isA<MailSent>(),
      );
      expect(
        await check(
          provider: MailProviderId.gmail,
          accountEmail: account,
          secret: 'wrong',
        ),
        isA<MailAuthFailed>(),
      );
      expect(await receivedMails(), isEmpty);
    });

    test('nothing of the user is in the logs of all of the above', () async {
      for (final text in [
        password,
        account,
        'One Click Scan - 2026',
        'not-the-password',
      ]) {
        expect(logger.all, isNot(contains(text)), reason: text);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('the secure storage (Android Keystore)', () {
    test('a password is written, read, replaced and deleted', () async {
      final store = SecureMailCredentialStore(
        store: const PluginSecureStringStore(),
        logger: logger,
      );
      await store.write(
        const StoredMailSecret(
          provider: MailProviderId.yahoo,
          accountEmail: 'other@example.test',
          secret: canarySecret,
        ),
      );

      final read = await store.read();
      expect(read!.provider, MailProviderId.yahoo);
      expect(read.accountEmail, 'other@example.test');
      expect(read.secret, canarySecret);

      await store.delete();
      expect(await store.read(), isNull);
    });

    test('at rest the password is encrypted: not in the clear in the files '
        'of the app', () async {
      final store = SecureMailCredentialStore(
        store: const PluginSecureStringStore(),
        logger: logger,
      );
      await store.write(
        const StoredMailSecret(
          provider: MailProviderId.gmail,
          accountEmail: account,
          secret: canarySecret,
        ),
      );

      final support = await getApplicationSupportDirectory();
      final dataDir = support.parent; // /data/user/0/<package>
      var checked = 0;
      // Where an app keeps preferences and databases (small files). The
      // models, the native libraries and the cache are big and hold no
      // settings, so they are not read.
      for (final name in ['shared_prefs', 'databases', 'no_backup']) {
        final folder = Directory('${dataDir.path}/$name');
        if (!folder.existsSync()) continue;
        for (final entity in folder.listSync(recursive: true)) {
          if (entity is! File) continue;
          try {
            // Inside the try: the plugin replaces its preferences file
            // (a .bak) while this loop runs, so a file can vanish.
            if (entity.lengthSync() > 5000000) continue;
            final text = latin1.decode(entity.readAsBytesSync());
            expect(text, isNot(contains(canarySecret)), reason: entity.path);
            checked++;
          } on FileSystemException {
            // A file that cannot be read cannot leak either.
          }
        }
      }
      report(
        'encrypted at rest: $checked files checked, none holds the password',
      );
      expect(checked, greaterThan(0));
    });
  });

  // -------------------------------------------------------------------------
  group('the share route', () {
    test('the intent carries the recipient, the subject, the text and the '
        'PDF with a read grant', () async {
      final described = await AndroidDraftSharer().describe(
        route: const GenericShareRoute(),
        to: const ['inbox@example.com'],
        subject: 'One Click Scan - 2026-10-21_19-05-12',
        body: 'Document scanned with One Click Scan.',
        documentUri: 'content://com.example.test/document/pdf%2Fx.pdf',
        mimeType: 'application/pdf',
      );

      expect(described['action'], 'android.intent.action.SEND');
      expect(described['type'], 'application/pdf');
      expect(described['to'], ['inbox@example.com']);
      expect(described['subject'], 'One Click Scan - 2026-10-21_19-05-12');
      expect(described['text'], 'Document scanned with One Click Scan.');
      expect(
        described['stream'],
        'content://com.example.test/document/pdf%2Fx.pdf',
      );
      expect(
        described['clip'],
        'content://com.example.test/document/pdf%2Fx.pdf',
      );
      expect(described['grantsRead'], isTrue);
      expect(described['grantsWrite'], isFalse);
    });

    test('the app of the provider: an explicit package, no generic menu, the '
        'PDF read-only', () async {
      final described = await AndroidDraftSharer().describe(
        route: const ProviderAppRoute('com.google.android.gm'),
        to: const ['inbox@example.com'],
        subject: 'One Click Scan - 2026-10-21_19-05-12',
        body: 'Document scanned with One Click Scan.',
        documentUri: 'content://com.example.test/document/pdf%2Fx.pdf',
        mimeType: 'application/pdf',
      );

      expect(described['action'], 'android.intent.action.SEND');
      expect(described['package'], 'com.google.android.gm');
      expect(described['route'], 'provider');
      expect(described['genericChooser'], isFalse);
      expect(described['to'], ['inbox@example.com']);
      expect(described['subject'], 'One Click Scan - 2026-10-21_19-05-12');
      expect(described['text'], 'Document scanned with One Click Scan.');
      expect(
        described['stream'],
        'content://com.example.test/document/pdf%2Fx.pdf',
      );
      expect(described['clip'], described['stream']);
      expect(described['grantsRead'], isTrue);
      expect(described['grantsWrite'], isFalse);
    });

    test('the only mail app: also explicit, no generic menu', () async {
      final described = await AndroidDraftSharer().describe(
        route: const SingleMailAppRoute('com.example.mail'),
        to: const [],
        subject: 's',
        body: 'b',
        documentUri: 'content://x/doc/1',
        mimeType: 'application/pdf',
      );
      expect(described['package'], 'com.example.mail');
      expect(described['genericChooser'], isFalse);
    });

    test('several mail apps: a chooser of exactly those, not the generic '
        'menu', () async {
      final described = await AndroidDraftSharer().describe(
        route: const MailAppChooserRoute(['a.mail', 'b.mail']),
        to: const [],
        subject: 's',
        body: 'b',
        documentUri: 'content://x/doc/1',
        mimeType: 'application/pdf',
      );
      expect(described['route'], 'chooser');
      expect(described['chooserPackages'], ['a.mail', 'b.mail']);
      expect(described['genericChooser'], isFalse);
      expect(described['grantsRead'], isTrue);
      expect(described['grantsWrite'], isFalse);
    });

    test('the generic menu is the last resort and the only one that says '
        'so', () async {
      final described = await AndroidDraftSharer().describe(
        route: const GenericShareRoute(),
        to: const [],
        subject: 's',
        body: 'b',
        documentUri: 'content://x/doc/1',
        mimeType: 'application/pdf',
      );
      expect(described['genericChooser'], isTrue);
      expect(described['package'], isNull);
    });

    test('the finder: this app counts as installed, a made-up package does '
        'not, and the list is of packages other than this app', () async {
      final finder = AndroidMailAppFinder();

      final own = await finder.find(
        providerPackage: 'com.example.one_click_scan',
      );
      expect(own.providerAppInstalled, isTrue);
      expect(own.mailtoPackages, isNot(contains('com.example.one_click_scan')));

      final none = await finder.find(providerPackage: 'no.such.app.example');
      expect(none.providerAppInstalled, isFalse);

      final noProvider = await finder.find();
      expect(noProvider.providerAppInstalled, isFalse);
    });

    test(
      'a link that is not https is refused natively (nothing is started)',
      () async {
        final opener = AndroidLinkOpener();
        for (final url in [
          'http://example.com/x',
          'file:///sdcard/x',
          'javascript:alert(1)',
          'intent://x#Intent;scheme=https;end',
          'not a link',
          '',
        ]) {
          expect(await opener.open(url), isFalse, reason: url);
        }
      },
    );

    test('with no recipient the list is empty', () async {
      final described = await AndroidDraftSharer().describe(
        route: const GenericShareRoute(),
        to: const [],
        subject: 's',
        body: 'b',
        documentUri: 'content://x/doc/1',
        mimeType: 'application/pdf',
      );
      expect(described['to'], isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('the whole screen flow (real OCR, real PDF, real mail)', () {
    late DirectoryScanFileStore folder;

    Future<void> startApp(WidgetTester tester, {MailProvider? provider}) async {
      final shots = Directory('${work.path}/shots')
        ..createSync(recursive: true);
      folder = DirectoryScanFileStore(
        Directory('${work.path}/user_folder')..createSync(recursive: true),
      );
      final container = await buildTestContainer(
        camera: _SyntheticCamera(shots, [greekPage]),
        scanFileStore: folder,
        scanTempStore: FakeScanTempStore(),
        ocr: ocr,
        pdf: PdfServices(builder: pdf.builder, opener: FakeOpenPdf()),
        mail: realMail(provider ?? providerFor()),
      );
      final repository = container<SettingsRepository>();
      await repository.save(
        (await repository.load()).copyWith(
          firstRunCompleted: true,
          storageFolder: testFolder,
          ocrPackId: OcrPackIds.greek,
          mailProvider: MailProviderId.gmail,
          senderAccount: account,
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

    tearDown(() {
      for (final name in ['user_folder', 'shots']) {
        final dir = Directory('${work.path}/$name');
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    });

    testWidgets('scan, PDF, Send: the mail that arrives carries the PDF that '
        'is in the folder, identical', (tester) async {
      await startApp(tester);
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pump();
      await pumpUntil(tester, find.byKey(ScanKeys.mailSend));

      await tester.ensureVisible(find.byKey(ScanKeys.mailSend));
      await tester.tap(find.byKey(ScanKeys.mailSend));
      await pumpUntil(
        tester,
        find.text('The message was sent from the e-mail server.'),
        timeout: const Duration(seconds: 60),
      );

      final storedPdf = File('${folder.root.path}/pdf/2026-10-21_19-05-12.pdf');
      expect(storedPdf.existsSync(), isTrue);
      final received = (await receivedMails()).single;
      expect(received['subject'], 'One Click Scan - 2026-10-21_19-05-12');
      final attachment = (received['attachments'] as List).single as Map;
      expect(attachment['name'], '2026-10-21_19-05-12.pdf');
      expect(
        attachment['sha256'],
        sha256.convert(storedPdf.readAsBytesSync()).toString(),
      );
      report(
        'screen flow: PDF ${storedPdf.lengthSync()} bytes sent and identical',
      );
    });

    testWidgets('the server is not there: a clear message, no crash, the PDF '
        'stays, and Try again works once it is back', (tester) async {
      await startApp(tester);
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pump();
      await pumpUntil(tester, find.byKey(ScanKeys.mailSend));
      await serverMode('hang');

      await tester.ensureVisible(find.byKey(ScanKeys.mailSend));
      await tester.tap(find.byKey(ScanKeys.mailSend));
      await pumpUntil(
        tester,
        find.byKey(ScanKeys.mailFailure),
        timeout: const Duration(seconds: 40),
      );

      expect(
        find.text(
          'Could not connect to the e-mail server. Check the internet '
          'and try again.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(ScanKeys.mailRetry), findsOneWidget);
      expect(find.byKey(ScanKeys.mailOpenApp), findsOneWidget);
      expect(find.byKey(ScanKeys.pdfOpen), findsOneWidget);
      expect(folder.files('pdf'), ['2026-10-21_19-05-12.pdf']);

      await serverMode('accept');
      await tester.tap(find.byKey(ScanKeys.mailRetry));
      await pumpUntil(
        tester,
        find.text('The message was sent from the e-mail server.'),
        timeout: const Duration(seconds: 60),
      );
      expect(await receivedMails(), hasLength(1));
    });
  });

  // -------------------------------------------------------------------------
  group('the settings screen', () {
    testWidgets('Test the connection, with the real sender: ok, refused, no '
        'server', (tester) async {
      tester.view.physicalSize = const Size(800, 3600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = await buildTestContainer(mail: realMail(providerFor()));
      final repository = container<SettingsRepository>();
      await repository.save(
        (await repository.load()).copyWith(
          firstRunCompleted: true,
          storageFolder: testFolder,
          mailProvider: MailProviderId.gmail,
          senderAccount: account,
        ),
      );
      await tester.pumpWidget(OneClickScanApp(container: container));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(HomeKeys.settings));
      await tester.pumpAndSettle();

      Future<void> test() async {
        await tester.ensureVisible(find.byKey(SettingsKeys.mailTest));
        await tester.tap(find.byKey(SettingsKeys.mailTest));
        final end = DateTime.now().add(const Duration(seconds: 40));
        while (find.byKey(SettingsKeys.mailTestResult).evaluate().isEmpty ||
            find.text('Testing the connection…').evaluate().isNotEmpty) {
          if (DateTime.now().isAfter(end)) fail('no result');
          await tester.pump(const Duration(milliseconds: 250));
        }
      }

      // The stored password (made in setUp) is used with the empty field.
      await test();
      expect(
        find.text('The server accepted the account. No message was sent.'),
        findsOneWidget,
      );
      expect(await receivedMails(), isEmpty);

      await tester.enterText(find.byKey(SettingsKeys.password), 'wrong');
      await tester.pumpAndSettle();
      await test();
      expect(find.textContaining('did not accept the account'), findsOneWidget);
    });
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
