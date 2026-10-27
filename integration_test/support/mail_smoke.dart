import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:one_click_scan/core/logging/app_logger.dart';
import 'package:one_click_scan/domain/entities/app_language.dart';
import 'package:one_click_scan/domain/entities/app_settings.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/pdf_page_input.dart';
import 'package:one_click_scan/domain/mail/mail_message.dart';
import 'package:one_click_scan/domain/mail/mail_outcome.dart';
import 'package:one_click_scan/domain/mail/mail_provider.dart';
import 'package:one_click_scan/domain/mail/share_route.dart';
import 'package:one_click_scan/domain/ports/attachment_source.dart';
import 'package:one_click_scan/domain/ports/mail_credential_store.dart';
import 'package:one_click_scan/domain/usecases/send_scan_pdf.dart';
import 'package:one_click_scan/services/mail/android_mail_channels.dart';
import 'package:one_click_scan/services/mail/secure_mail_credential_store.dart';
import 'package:one_click_scan/services/mail/smtp_mail_sender.dart';
import 'package:path_provider/path_provider.dart';

import '../../test/support/mail_fakes.dart' show testLocalProvider;
import '../../tool/smtp_test_server.dart';

/// The mail part of the release smoke (R8 on, no network of the outside world):
/// the secure storage (Android Keystore) writes, reads and deletes a password;
/// the real SMTP sender (the `mailer` package in its isolate) sends a message
/// with a PDF to a server that runs in this same process on the loopback; the
/// message that arrives has the subject, the addresses and an attachment that
/// is the file, byte for byte. Everything is invented; nothing leaves the phone.
Future<String> runMailSmoke() async {
  const secret = 'smoke-test-password';
  const account = 'user@example.test';
  final server = await TestSmtpServer.start(password: secret);
  final dir = await Directory(
    '${(await getTemporaryDirectory()).path}/mail_smoke',
  ).create(recursive: true);
  try {
    // The Keystore.
    final store = SecureMailCredentialStore(
      store: const PluginSecureStringStore(),
      logger: const DebugAppLogger(),
    );
    await store.write(
      const StoredMailSecret(
        provider: MailProviderId.gmail,
        accountEmail: account,
        secret: secret,
      ),
    );
    final back = await store.read();
    if (back == null || back.secret != secret || back.accountEmail != account) {
      throw StateError('the secure storage did not return the password');
    }

    // The message and the real SMTP sender.
    final bytes = Uint8List.fromList(
      List<int>.generate(200000, (i) => (i * 13) % 256),
    );
    final pdf = File('${dir.path}/2026-10-21_19-05-12.pdf')
      ..writeAsBytesSync([...'%PDF-1.7\n'.codeUnits, ...bytes]);
    final stored = StoredPdf(
      fileName: '2026-10-21_19-05-12.pdf',
      uri: pdf.uri.toString(),
      pageCount: 1,
      textPageCount: 1,
      byteSize: pdf.lengthSync(),
    );
    final send = SendScanPdf(
      sender: SmtpMailSender(
        logger: const DebugAppLogger(),
        socketTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 40),
      ),
      attachments: _LocalFiles(),
      credentials: store,
      providers: MailProviderRegistry({
        MailProviderId.gmail: testLocalProvider(port: server.port),
        MailProviderId.outlook: testLocalProvider(port: server.port),
        MailProviderId.yahoo: testLocalProvider(port: server.port),
      }),
      logger: const DebugAppLogger(),
    );
    final clock = Stopwatch()..start();
    final outcome = await send(
      settings: const AppSettings(
        language: AppLanguage.el,
        mailProvider: MailProviderId.gmail,
        senderAccount: account,
      ),
      pdf: stored,
    );
    clock.stop();
    if (outcome is! MailSent) {
      throw StateError('the send ended as ${outcome.runtimeType}');
    }
    final mail = server.mails.single;
    final attachment = mail.attachments.single;
    final fileHash = sha256.convert(pdf.readAsBytesSync()).toString();
    if (attachment.sha256Hex != fileHash) {
      throw StateError('the attachment is not the file');
    }
    if (mail.subject != 'One Click Scan - 2026-10-21_19-05-12' ||
        mail.from != account ||
        mail.to.single != account ||
        mail.bodyText.trim() != 'Σαρωμένο έγγραφο από το One Click Scan.') {
      throw StateError('the message is not the expected one');
    }

    await store.delete();
    if (await store.read() != null) {
      throw StateError('the password was not deleted');
    }
    final intents = await _checkIntents();
    return 'mail: keystore ok, sent ${attachment.bytes.length} bytes with an '
        'identical attachment in ${clock.elapsedMilliseconds} ms, $intents';
  } finally {
    await server.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

/// The PDF already is a local file in the smoke.
class _LocalFiles implements AttachmentSource {
  @override
  Future<MailAttachment> prepare(StoredPdf pdf) async => MailAttachment(
    fileName: pdf.fileName,
    mimeType: 'application/pdf',
    path: Uri.parse(pdf.uri).toFilePath(),
  );

  @override
  Future<void> release(MailAttachment attachment) async {}

  @override
  Future<void> purgeAll() async {}
}

/// Builds the share intents of every route in the release build (R8 on) and asks
/// the phone for its e-mail apps and for the install state of a package. Nothing
/// is started: `describeShare` only reports what the intent carries.
Future<String> _checkIntents() async {
  final sharer = AndroidDraftSharer();
  Future<Map<String, Object?>> describe(DraftShareRoute route) =>
      sharer.describe(
        route: route,
        to: const ['inbox@example.com'],
        subject: 'One Click Scan - 2026-10-21_19-05-12',
        body: 'Document scanned with One Click Scan.',
        documentUri: 'content://com.example.test/document/pdf%2Fx.pdf',
        mimeType: 'application/pdf',
      );

  final provider = await describe(
    const ProviderAppRoute('com.google.android.gm'),
  );
  final single = await describe(const SingleMailAppRoute('com.example.mail'));
  final chooser = await describe(
    const MailAppChooserRoute(['a.mail', 'b.mail']),
  );
  final generic = await describe(const GenericShareRoute());
  for (final d in [provider, single, chooser, generic]) {
    if (d['action'] != 'android.intent.action.SEND' ||
        d['grantsRead'] != true ||
        d['grantsWrite'] != false ||
        d['subject'] != 'One Click Scan - 2026-10-21_19-05-12') {
      throw StateError('a share intent is not as expected: $d');
    }
  }
  if (provider['package'] != 'com.google.android.gm' ||
      single['package'] != 'com.example.mail' ||
      provider['genericChooser'] != false ||
      chooser['genericChooser'] != false ||
      generic['genericChooser'] != true ||
      generic['package'] != null) {
    throw StateError('the routes are not as expected');
  }
  final finder = AndroidMailAppFinder();
  final own = await finder.find(providerPackage: 'com.example.one_click_scan');
  final missing = await finder.find(providerPackage: 'no.such.app.example');
  if (!own.providerAppInstalled || missing.providerAppInstalled) {
    throw StateError('the install check is not as expected');
  }
  if (await AndroidLinkOpener().open('http://example.com/x')) {
    throw StateError('a link that is not https was opened');
  }
  return 'intents ok (4 routes, ${own.mailtoPackages.length} mail apps)';
}
