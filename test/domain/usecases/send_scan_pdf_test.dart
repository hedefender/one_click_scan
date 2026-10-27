import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/app_language.dart';
import 'package:one_click_scan/domain/entities/app_settings.dart';
import 'package:one_click_scan/domain/entities/destination_mode.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/pdf_page_input.dart';
import 'package:one_click_scan/domain/mail/mail_cancellation.dart';
import 'package:one_click_scan/domain/mail/mail_outcome.dart';
import 'package:one_click_scan/domain/mail/mail_provider.dart';
import 'package:one_click_scan/domain/mail/mail_size_policy.dart';
import 'package:one_click_scan/domain/ports/draft_sharer.dart';
import 'package:one_click_scan/domain/ports/mail_credential_store.dart';
import 'package:one_click_scan/domain/usecases/send_scan_pdf.dart';

import '../../support/mail_fakes.dart';

StoredPdf pdfOf({
  int bytes = 200000,
  String name = '2026-10-21_19-05-12.pdf',
}) => StoredPdf(
  fileName: name,
  uri: 'content://com.example.test/document/pdf%2F$name',
  pageCount: 2,
  textPageCount: 2,
  byteSize: bytes,
);

AppSettings settingsOf({
  MailProviderId? provider = MailProviderId.gmail,
  String? sender = testAccount,
  DestinationMode mode = DestinationMode.own,
  String? custom,
  AppLanguage language = AppLanguage.en,
}) => AppSettings(
  language: language,
  mailProvider: provider,
  senderAccount: sender,
  destinationMode: mode,
  customDestination: custom,
);

void main() {
  late FakeMailSender sender;
  late FakeMailCredentialStore credentials;
  late FakeAttachmentSource attachments;
  late CapturingLogger logger;
  late SendScanPdf send;

  setUp(() {
    sender = FakeMailSender();
    credentials = FakeMailCredentialStore()
      ..stored = const StoredMailSecret(
        provider: MailProviderId.gmail,
        accountEmail: testAccount,
        secret: canarySecret,
      );
    attachments = FakeAttachmentSource();
    logger = CapturingLogger();
    send = SendScanPdf(
      sender: sender,
      attachments: attachments,
      credentials: credentials,
      providers: MailProviderRegistry.standard,
      logger: logger,
    );
  });

  group('the message', () {
    test('subject from the name of the PDF, one neutral line, only the PDF, '
        'from the account to the destination', () async {
      final outcome = await send(settings: settingsOf(), pdf: pdfOf());

      expect(outcome, isA<MailSent>());
      final message = sender.sent.single;
      expect(message.subject, 'One Click Scan - 2026-10-21_19-05-12');
      expect(message.body, 'Document scanned with One Click Scan.');
      expect(message.from, testAccount);
      // "my own address": the destination is the account itself.
      expect(message.to, [testAccount]);
      expect(message.attachments, hasLength(1));
      expect(message.attachments.single.fileName, '2026-10-21_19-05-12.pdf');
      expect(message.attachments.single.mimeType, 'application/pdf');
    });

    test('another address: the message goes there, from the account', () async {
      await send(
        settings: settingsOf(
          mode: DestinationMode.custom,
          custom: testDestination,
        ),
        pdf: pdfOf(),
      );

      expect(sender.sent.single.from, testAccount);
      expect(sender.sent.single.to, [testDestination]);
    });

    test('the body follows the language of the app', () async {
      await send(
        settings: settingsOf(language: AppLanguage.el),
        pdf: pdfOf(),
      );
      expect(
        sender.sent.single.body,
        'Σαρωμένο έγγραφο από το One Click Scan.',
      );
    });

    test('a second scan with the same stem has a different subject '
        '(-2 in the name)', () async {
      await send(
        settings: settingsOf(),
        pdf: pdfOf(name: 'a-2.pdf'),
      );
      expect(sender.sent.single.subject, 'One Click Scan - a-2');
    });

    test('the message is signed in with the stored password and the provider '
        'of the settings', () async {
      await send(
        settings: settingsOf(provider: MailProviderId.gmail),
        pdf: pdfOf(),
      );
      expect(sender.auths.single.secret, canarySecret);
      expect(sender.auths.single.accountEmail, testAccount);
      expect(sender.providers.single.id, 'gmail');
    });

    test('the PDF copy is made before the send and deleted after it', () async {
      await send(settings: settingsOf(), pdf: pdfOf());
      expect(attachments.prepared, hasLength(1));
      expect(attachments.released, hasLength(1));
      expect(attachments.released.single.path, sender.readAttachments.single);
    });
  });

  group('settings that are not complete', () {
    test('no provider', () async {
      final outcome = await send(
        settings: settingsOf(provider: null),
        pdf: pdfOf(),
      );
      expect(
        outcome,
        isA<MailNotConfigured>().having(
          (o) => o.reason,
          'reason',
          MailNotConfiguredReason.provider,
        ),
      );
    });

    test('no account or a wrong one', () async {
      for (final account in [null, '', 'not-an-address']) {
        final outcome = await send(
          settings: settingsOf(sender: account),
          pdf: pdfOf(),
        );
        expect(
          (outcome as MailNotConfigured).reason,
          MailNotConfiguredReason.account,
        );
      }
    });

    test('another address that is not an address', () async {
      final outcome = await send(
        settings: settingsOf(mode: DestinationMode.custom, custom: 'nope'),
        pdf: pdfOf(),
      );
      expect(
        (outcome as MailNotConfigured).reason,
        MailNotConfiguredReason.destination,
      );
    });

    test('no stored password', () async {
      credentials.stored = null;
      final outcome = await send(settings: settingsOf(), pdf: pdfOf());
      expect(
        (outcome as MailNotConfigured).reason,
        MailNotConfiguredReason.password,
      );
    });

    test('a password of another provider or account is not used', () async {
      credentials.stored = const StoredMailSecret(
        provider: MailProviderId.yahoo,
        accountEmail: testAccount,
        secret: canarySecret,
      );
      var outcome = await send(settings: settingsOf(), pdf: pdfOf());
      expect(outcome, isA<MailNotConfigured>());

      credentials.stored = const StoredMailSecret(
        provider: MailProviderId.gmail,
        accountEmail: 'someone.else@example.test',
        secret: canarySecret,
      );
      outcome = await send(settings: settingsOf(), pdf: pdfOf());
      expect(outcome, isA<MailNotConfigured>());
    });

    test('nothing is read or sent in any of these cases', () async {
      credentials.stored = null;
      await send(settings: settingsOf(), pdf: pdfOf());
      await send(settings: settingsOf(provider: null), pdf: pdfOf());
      expect(sender.sent, isEmpty);
      expect(attachments.prepared, isEmpty);
    });
  });

  group('size', () {
    test(
      'a PDF over the limit of the provider is not read and not sent',
      () async {
        final limit = MailSizePolicy.maxAttachmentBytes(
          MailProviderRegistry.standard.resolve(MailProviderId.outlook),
        );
        final outcome = await send(
          settings: settingsOf(provider: MailProviderId.outlook),
          pdf: pdfOf(bytes: limit + 1),
        );
        // The password is for Gmail here, so first make it Outlook's.
        expect(outcome, isA<MailNotConfigured>());

        credentials.stored = const StoredMailSecret(
          provider: MailProviderId.outlook,
          accountEmail: testAccount,
          secret: canarySecret,
        );
        final tooBig = await send(
          settings: settingsOf(provider: MailProviderId.outlook),
          pdf: pdfOf(bytes: limit + 1),
        );
        expect(tooBig, isA<MailTooLarge>());
        expect(sender.sent, isEmpty);
        expect(attachments.prepared, isEmpty);

        final ok = await send(
          settings: settingsOf(provider: MailProviderId.outlook),
          pdf: pdfOf(bytes: limit),
        );
        expect(ok, isA<MailSent>());
      },
    );

    test('the limit differs by provider: the same PDF goes by Gmail and not '
        'by Outlook', () async {
      const size = 16000000;
      credentials.stored = const StoredMailSecret(
        provider: MailProviderId.outlook,
        accountEmail: testAccount,
        secret: canarySecret,
      );
      expect(
        await send(
          settings: settingsOf(provider: MailProviderId.outlook),
          pdf: pdfOf(bytes: size),
        ),
        isA<MailTooLarge>(),
      );
      credentials.stored = const StoredMailSecret(
        provider: MailProviderId.gmail,
        accountEmail: testAccount,
        secret: canarySecret,
      );
      expect(
        await send(
          settings: settingsOf(),
          pdf: pdfOf(bytes: size),
        ),
        isA<MailSent>(),
      );
    });
  });

  group('every end of the sender is passed on, and the copy is deleted', () {
    final outcomes = <MailOutcome>[
      const MailAuthFailed(),
      const MailNetworkError(),
      const MailTooLarge(),
      const MailRejected(550),
      const MailCancelled(),
      const MailUnknown(),
    ];
    for (final expected in outcomes) {
      test('${expected.runtimeType}', () async {
        sender.outcome = expected;
        final outcome = await send(settings: settingsOf(), pdf: pdfOf());
        expect(outcome.runtimeType, expected.runtimeType);
        expect(attachments.released, hasLength(1));
      });
    }

    test('a sender that throws is an unknown outcome, not a crash, and the '
        'secret is not logged', () async {
      sender.throwOnSend = Exception('boom $canarySecret $testAccount');
      final outcome = await send(settings: settingsOf(), pdf: pdfOf());

      expect(outcome, isA<MailUnknown>());
      expect(attachments.released, hasLength(1));
      expect(logger.all, isNot(contains(canarySecret)));
      expect(logger.all, isNot(contains(testAccount)));
    });

    test('a PDF that cannot be read is an unknown outcome', () async {
      attachments.unavailable = true;
      final outcome = await send(settings: settingsOf(), pdf: pdfOf());
      expect(outcome, isA<MailUnknown>());
      expect(sender.sent, isEmpty);
    });

    test('a send cancelled before it starts is not started', () async {
      final cancellation = MailCancellation()..cancel();
      final outcome = await send(
        settings: settingsOf(),
        pdf: pdfOf(),
        cancellation: cancellation,
      );
      expect(outcome, isA<MailCancelled>());
      expect(sender.sent, isEmpty);
      expect(attachments.prepared, isEmpty);
    });
  });

  group('the other use cases', () {
    test('share draft: the recipient, the same subject and body, the document '
        'URI of the PDF', () async {
      final sharer = FakeDraftSharer();
      final share = ShareScanPdfDraft(
        sharer: sharer,
        finder: FakeMailAppFinder(),
        providers: MailProviderRegistry.standard,
      );
      final pdf = pdfOf();

      final result = await share(
        settings: settingsOf(
          mode: DestinationMode.custom,
          custom: testDestination,
        ),
        pdf: pdf,
      );

      expect(result, DraftShareResult.opened);
      final shared = sharer.shared.single;
      expect(shared['to'], [testDestination]);
      expect(shared['subject'], 'One Click Scan - 2026-10-21_19-05-12');
      expect(shared['body'], 'Document scanned with One Click Scan.');
      expect(shared['uri'], pdf.uri);
      expect(shared['mimeType'], 'application/pdf');
    });

    test(
      'share draft works without an account: the recipient is left empty',
      () async {
        final sharer = FakeDraftSharer();
        await ShareScanPdfDraft(
          sharer: sharer,
          finder: FakeMailAppFinder(),
          providers: MailProviderRegistry.standard,
        )(settings: settingsOf(provider: null, sender: null), pdf: pdfOf());
        expect(sharer.shared.single['to'], isEmpty);
      },
    );

    test('the connection check signs in with the screen values and sends '
        'nothing', () async {
      final check = CheckMailConnection(
        sender: sender,
        providers: MailProviderRegistry.standard,
      );
      final outcome = await check(
        provider: MailProviderId.yahoo,
        accountEmail: testAccount,
        secret: canarySecret,
      );

      expect(outcome, isA<MailSent>());
      expect(sender.checks, 1);
      expect(sender.sent, isEmpty);
      expect(sender.providers.single.id, 'yahoo');
    });

    test('the connection check needs a provider', () async {
      final check = CheckMailConnection(
        sender: sender,
        providers: MailProviderRegistry.standard,
      );
      final outcome = await check(
        provider: null,
        accountEmail: testAccount,
        secret: canarySecret,
      );
      expect(outcome, isA<MailNotConfigured>());
      expect(sender.checks, 0);
    });
  });
}
