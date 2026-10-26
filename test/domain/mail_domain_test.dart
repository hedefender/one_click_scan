import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/app_language.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/mail/mail_auth.dart';
import 'package:one_click_scan/domain/mail/mail_message.dart';
import 'package:one_click_scan/domain/mail/mail_provider.dart';
import 'package:one_click_scan/domain/mail/mail_size_policy.dart';
import 'package:one_click_scan/domain/mail/mail_text.dart';
import 'package:one_click_scan/domain/ports/mail_credential_store.dart';

import '../support/mail_fakes.dart';

void main() {
  group('the provider registry', () {
    const registry = MailProviderRegistry.standard;

    test('has the three providers of the wizard, with the facts of '
        'MAIL_PROVIDERS.md', () {
      final gmail = registry.resolve(MailProviderId.gmail);
      expect(gmail.smtp.host, 'smtp.gmail.com');
      expect(gmail.smtp.port, 465);
      expect(gmail.smtp.security, SmtpSecurity.implicitTls);

      final outlook = registry.resolve(MailProviderId.outlook);
      expect(outlook.smtp.host, 'smtp-mail.outlook.com');
      expect(outlook.smtp.port, 587);
      expect(outlook.smtp.security, SmtpSecurity.startTls);

      final yahoo = registry.resolve(MailProviderId.yahoo);
      expect(yahoo.smtp.host, 'smtp.mail.yahoo.com');
      expect(yahoo.smtp.port, 465);
      expect(yahoo.smtp.security, SmtpSecurity.implicitTls);
    });

    test(
      'every provider can be asked of every choice, none is without TLS',
      () {
        for (final id in MailProviderId.values) {
          final provider = registry.resolve(id);
          expect(provider.smtp.security, isNot(SmtpSecurity.plain));
          expect(provider.supports(MailAuthKind.appPassword), isTrue);
          // OAuth is planned (MAIL_OAUTH_PLAN.md), not built.
          expect(provider.supports(MailAuthKind.oauth), isFalse);
        }
      },
    );

    test('Outlook.com app passwords are marked as not confirmed, the others '
        'as supported', () {
      expect(
        registry.resolve(MailProviderId.outlook).appPasswordSupport,
        AppPasswordSupport.unconfirmed,
      );
      expect(
        registry.resolve(MailProviderId.gmail).appPasswordSupport,
        AppPasswordSupport.supported,
      );
      expect(
        registry.resolve(MailProviderId.yahoo).appPasswordSupport,
        AppPasswordSupport.supported,
      );
    });

    test('the Yahoo size limit is flagged as an assumption', () {
      expect(
        registry.resolve(MailProviderId.yahoo).sizeLimitConfirmed,
        isFalse,
      );
      expect(registry.resolve(MailProviderId.gmail).sizeLimitConfirmed, isTrue);
    });

    test('testLocal is not in the app: only tests make that provider', () {
      expect(registry.all.map((p) => p.id), ['gmail', 'outlook', 'yahoo']);
      expect(testLocalProvider(port: 1).id, 'testLocal');
      expect(testLocalProvider(port: 1).smtp.security, SmtpSecurity.plain);
    });
  });

  group('the size policy', () {
    test(
      'the factor is base64 (4/3) with a line break every 76 characters',
      () {
        expect(MailSizePolicy.encodingFactor, closeTo(1.3684, 0.0001));
      },
    );

    test('the factor matches a real encoding of a file', () {
      final bytes = List<int>.generate(3000000, (i) => i % 251);
      final encoded = base64.encode(bytes);
      // CRLF after every 76 characters, as in MIME.
      final lines = (encoded.length / 76).ceil();
      final size = encoded.length + lines * 2;
      expect(
        size / bytes.length,
        closeTo(MailSizePolicy.encodingFactor, 0.001),
      );
    });

    test(
      'the biggest PDF is the limit over the factor, after the headroom',
      () {
        final gmail = MailProviderRegistry.standard.resolve(
          MailProviderId.gmail,
        );
        final outlook = MailProviderRegistry.standard.resolve(
          MailProviderId.outlook,
        );
        final yahoo = MailProviderRegistry.standard.resolve(
          MailProviderId.yahoo,
        );

        // About 18.2 MB for Gmail, 14.6 MB for the 20 MB providers.
        expect(MailSizePolicy.maxAttachmentBytes(gmail), closeTo(18221339, 5));
        expect(
          MailSizePolicy.maxAttachmentBytes(outlook),
          closeTo(14567600, 1000),
        );
        expect(
          MailSizePolicy.maxAttachmentBytes(yahoo),
          MailSizePolicy.maxAttachmentBytes(outlook),
        );
        // Always under the limit as a message.
        for (final p in [gmail, outlook, yahoo]) {
          final max = MailSizePolicy.maxAttachmentBytes(p);
          expect(
            MailSizePolicy.encodedMessageBytes(max),
            lessThanOrEqualTo(p.maxMessageBytes),
          );
          // And always under what the PDF alone would allow without the factor.
          expect(max, lessThan(p.maxMessageBytes * 3 / 4 + 1));
        }
      },
    );

    test('fits is inclusive at the limit and false one byte above', () {
      final p = testLocalProvider(port: 1, maxMessageBytes: 1000000);
      final max = MailSizePolicy.maxAttachmentBytes(p);
      expect(MailSizePolicy.fits(p, max), isTrue);
      expect(MailSizePolicy.fits(p, max + 1), isFalse);
      expect(MailSizePolicy.fits(p, 0), isTrue);
    });

    test('a limit smaller than the headroom takes nothing', () {
      final p = testLocalProvider(port: 1, maxMessageBytes: 100);
      expect(MailSizePolicy.maxAttachmentBytes(p), 0);
      expect(MailSizePolicy.fits(p, 1), isFalse);
    });
  });

  group('the words of the message', () {
    test('the subject is "One Click Scan - " and the name of the PDF without '
        '.pdf', () {
      expect(
        MailText.subject('2026-10-21_19-05-12.pdf'),
        'One Click Scan - 2026-10-21_19-05-12',
      );
      expect(
        MailText.subject('2026-10-21_19-05-12-2.pdf'),
        'One Click Scan - 2026-10-21_19-05-12-2',
      );
      expect(MailText.subject('x.PDF'), 'One Click Scan - x');
      expect(MailText.subject('noextension'), 'One Click Scan - noextension');
    });

    test('every subject starts with the same fixed words (a mail rule)', () {
      for (final name in ['a.pdf', 'b-2.pdf', 'c-3.pdf']) {
        expect(
          MailText.subject(name),
          startsWith('${MailText.subjectPrefix} - '),
        );
      }
    });

    test('the body is one neutral line in the language of the app', () {
      final el = MailText.body(AppLanguage.el);
      final en = MailText.body(AppLanguage.en);
      expect(el, 'Σαρωμένο έγγραφο από το One Click Scan.');
      expect(en, 'Document scanned with One Click Scan.');
      expect(el.contains('\n'), isFalse);
      expect(en.contains('\n'), isFalse);
    });
  });

  group('secrets never print', () {
    test('toString of the auth, the stored secret and the message', () {
      const auth = AppPasswordAuth(
        accountEmail: testAccount,
        secret: canarySecret,
      );
      const stored = StoredMailSecret(
        provider: MailProviderId.gmail,
        accountEmail: testAccount,
        secret: canarySecret,
      );
      const message = MailMessage(
        from: testAccount,
        to: [testDestination],
        subject: 's',
        body: 'b',
        attachments: [],
      );
      for (final text in ['$auth', '$stored', '$message']) {
        expect(text, isNot(contains(canarySecret)));
        expect(text, isNot(contains('example')));
      }
    });

    test('a stored secret belongs to its provider and account only', () {
      const stored = StoredMailSecret(
        provider: MailProviderId.gmail,
        accountEmail: 'User@Example.test',
        secret: canarySecret,
      );
      expect(
        stored.belongsTo(MailProviderId.gmail, 'user@example.test'),
        isTrue,
      );
      expect(
        stored.belongsTo(MailProviderId.gmail, ' USER@example.test '),
        isTrue,
      );
      expect(
        stored.belongsTo(MailProviderId.outlook, 'user@example.test'),
        isFalse,
      );
      expect(
        stored.belongsTo(MailProviderId.gmail, 'other@example.test'),
        isFalse,
      );
      expect(stored.belongsTo(MailProviderId.gmail, null), isFalse);
    });
  });
}
