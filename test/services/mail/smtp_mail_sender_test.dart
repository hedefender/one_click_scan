import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/mail/mail_auth.dart';
import 'package:one_click_scan/domain/mail/mail_cancellation.dart';
import 'package:one_click_scan/domain/mail/mail_message.dart';
import 'package:one_click_scan/domain/mail/mail_outcome.dart';
import 'package:one_click_scan/services/mail/smtp_mail_sender.dart';

import '../../../tool/smtp_test_server.dart';
import '../../support/mail_fakes.dart';

/// The real sender (the `mailer` package in its own isolate) against a real
/// SMTP server on the loopback of this computer (`tool/smtp_test_server.dart`).
/// Nothing leaves the machine and no real account is involved.
void main() {
  late TestSmtpServer server;
  late Directory work;
  late File pdf;
  late CapturingLogger logger;
  late SmtpMailSender sender;

  const auth = AppPasswordAuth(
    accountEmail: 'user@example.test',
    secret: 'test-password',
  );

  setUp(() async {
    server = await TestSmtpServer.start();
    work = await Directory.systemTemp.createTemp('mail_test');
    // A "PDF" of 300 KB of every byte value: binary, so a wrong encoding shows.
    final bytes = Uint8List.fromList(
      List<int>.generate(300000, (i) => (i * 7 + i ~/ 256) % 256),
    );
    pdf = File('${work.path}/2026-10-21_19-05-12.pdf')
      ..writeAsBytesSync([...ascii.encode('%PDF-1.7\n'), ...bytes]);
    logger = CapturingLogger();
    sender = SmtpMailSender(
      logger: logger,
      socketTimeout: const Duration(seconds: 5),
      sendTimeout: const Duration(seconds: 20),
    );
  });

  tearDown(() async {
    await server.close();
    await work.delete(recursive: true);
  });

  MailMessage message({String body = 'Document scanned with One Click Scan.'}) {
    return MailMessage(
      from: 'user@example.test',
      to: const ['inbox@example.com'],
      subject: 'One Click Scan - 2026-10-21_19-05-12',
      body: body,
      attachments: [
        MailAttachment(
          fileName: '2026-10-21_19-05-12.pdf',
          mimeType: 'application/pdf',
          path: pdf.path,
        ),
      ],
    );
  }

  Future<MailOutcome> sendWith({
    MailAuth credentials = auth,
    MailMessage? msg,
    int? port,
    MailCancellation? cancellation,
  }) {
    return sender.send(
      message: msg ?? message(),
      auth: credentials,
      provider: testLocalProvider(port: port ?? server.port),
      cancellation: cancellation,
    );
  }

  test('a message arrives with the right subject, from, to and body, and '
      'the attachment is the file byte for byte', () async {
    final outcome = await sendWith();

    expect(outcome, isA<MailSent>());
    expect(server.mails, hasLength(1));
    final mail = server.mails.single;
    expect(mail.from, 'user@example.test');
    expect(mail.to, ['inbox@example.com']);
    expect(mail.subject, 'One Click Scan - 2026-10-21_19-05-12');
    expect(mail.bodyText.trim(), 'Document scanned with One Click Scan.');
    expect(mail.attachments, hasLength(1));
    final attachment = mail.attachments.single;
    expect(attachment.name, '2026-10-21_19-05-12.pdf');
    expect(attachment.bytes, pdf.readAsBytesSync());
    expect(
      attachment.sha256Hex,
      sha256.convert(pdf.readAsBytesSync()).toString(),
    );
  });

  test('a Greek body is carried in UTF-8', () async {
    final outcome = await sendWith(
      msg: message(body: 'Σαρωμένο έγγραφο από το One Click Scan.'),
    );

    expect(outcome, isA<MailSent>());
    expect(
      server.mails.single.bodyText.trim(),
      'Σαρωμένο έγγραφο από το One Click Scan.',
    );
  });

  test('a wrong password is authFailed and nothing is delivered', () async {
    final outcome = await sendWith(
      credentials: const AppPasswordAuth(
        accountEmail: 'user@example.test',
        secret: 'not-the-password',
      ),
    );

    expect(outcome, isA<MailAuthFailed>());
    expect(server.mails, isEmpty);
  });

  test('the server answers 535 to everyone: authFailed', () async {
    server.mode = SmtpMode.authFail;
    expect(await sendWith(), isA<MailAuthFailed>());
  });

  test('552 after the message is tooLarge', () async {
    server.mode = SmtpMode.tooLarge;
    expect(await sendWith(), isA<MailTooLarge>());
    expect(server.mails, isEmpty);
  });

  test('550 to the recipient is a rejection with its code', () async {
    server.mode = SmtpMode.rejectRecipient;
    final outcome = await sendWith();

    expect(outcome, isA<MailRejected>());
    expect((outcome as MailRejected).code, 550);
  });

  test('a server that is not there is a network outcome, fast', () async {
    final port = server.port;
    await server.close();
    final stopwatch = Stopwatch()..start();

    final outcome = await sendWith(port: port);

    expect(outcome, isA<MailNetworkError>());
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test('a server that never speaks ends with a timeout, as a network '
      'outcome', () async {
    server.mode = SmtpMode.hang;
    final slow = SmtpMailSender(
      logger: logger,
      socketTimeout: const Duration(seconds: 1),
      sendTimeout: const Duration(seconds: 6),
    );
    final stopwatch = Stopwatch()..start();

    final outcome = await slow.send(
      message: message(),
      auth: auth,
      provider: testLocalProvider(port: server.port),
    );

    expect(outcome, isA<MailNetworkError>());
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 8)));
  });

  test('cancel stops a send at once', () async {
    server.mode = SmtpMode.hang;
    final cancellation = MailCancellation();
    final started = Stopwatch()..start();

    final future = sendWith(cancellation: cancellation);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    cancellation.cancel();
    final outcome = await future;

    expect(outcome, isA<MailCancelled>());
    expect(started.elapsed, lessThan(const Duration(seconds: 3)));
    expect(server.mails, isEmpty);
  });

  test('cancelled before it starts: no connection is made', () async {
    final cancellation = MailCancellation()..cancel();
    final outcome = await sendWith(cancellation: cancellation);

    expect(outcome, isA<MailCancelled>());
    expect(server.mails, isEmpty);
  });

  test('after a failure a new try works', () async {
    server.mode = SmtpMode.authFail;
    expect(await sendWith(), isA<MailAuthFailed>());
    server.mode = SmtpMode.tooLarge;
    expect(await sendWith(), isA<MailTooLarge>());

    server.mode = SmtpMode.accept;
    expect(await sendWith(), isA<MailSent>());
    expect(server.mails, hasLength(1));
  });

  test('a file that is not there is an outcome, not an exception', () async {
    pdf.deleteSync();
    final outcome = await sendWith();

    expect(outcome, isNot(isA<MailSent>()));
    expect(server.mails, isEmpty);
  });

  group('the connection check', () {
    test('signs in and sends nothing', () async {
      final outcome = await sender.checkConnection(
        auth: auth,
        provider: testLocalProvider(port: server.port),
      );

      expect(outcome, isA<MailSent>());
      expect(server.mails, isEmpty);
    });

    test('a wrong password is authFailed', () async {
      final outcome = await sender.checkConnection(
        auth: const AppPasswordAuth(
          accountEmail: 'user@example.test',
          secret: 'wrong',
        ),
        provider: testLocalProvider(port: server.port),
      );
      expect(outcome, isA<MailAuthFailed>());
    });

    test('no server is network', () async {
      final port = server.port;
      await server.close();
      final outcome = await sender.checkConnection(
        auth: auth,
        provider: testLocalProvider(port: port),
      );
      expect(outcome, isA<MailNetworkError>());
    });
  });

  test('nothing of the user is logged by a failing send', () async {
    server.mode = SmtpMode.authFail;
    await sendWith(
      credentials: const AppPasswordAuth(
        accountEmail: 'user@example.test',
        secret: canarySecret,
      ),
    );
    final port = server.port;
    await server.close();
    await sendWith(port: port);

    for (final secret in [
      canarySecret,
      'user@example.test',
      'inbox@example.com',
      'One Click Scan - 2026',
    ]) {
      expect(logger.all, isNot(contains(secret)));
    }
  });

  test('many sends in a row leave no isolate or connection behind', () async {
    for (var i = 0; i < 5; i++) {
      expect(await sendWith(), isA<MailSent>());
    }
    expect(server.mails, hasLength(5));
  });
}
