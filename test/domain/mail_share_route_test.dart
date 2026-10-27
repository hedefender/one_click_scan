import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/mail/mail_outcome.dart';
import 'package:one_click_scan/domain/mail/mail_provider.dart';
import 'package:one_click_scan/domain/mail/share_route.dart';
import 'package:one_click_scan/domain/ports/draft_sharer.dart';
import 'package:one_click_scan/domain/usecases/send_scan_pdf.dart';

import '../support/mail_fakes.dart';
import 'usecases/send_scan_pdf_test.dart' show pdfOf, settingsOf;

void main() {
  const registry = MailProviderRegistry.standard;

  group('the packages and the guide pages of the registry', () {
    test('each provider has its own app package', () {
      expect(
        registry.resolve(MailProviderId.gmail).appPackage,
        'com.google.android.gm',
      );
      expect(
        registry.resolve(MailProviderId.outlook).appPackage,
        'com.microsoft.office.outlook',
      );
      expect(
        registry.resolve(MailProviderId.yahoo).appPackage,
        'com.yahoo.mobile.client.android.mail',
      );
    });

    test('Gmail and Yahoo have a guide page, Outlook has none', () {
      expect(
        registry.guideUrlFor(MailProviderId.gmail),
        'https://myaccount.google.com/apppasswords',
      );
      expect(
        registry.guideUrlFor(MailProviderId.yahoo),
        'https://login.yahoo.com/account/security',
      );
      expect(registry.guideUrlFor(MailProviderId.outlook), isNull);
    });

    test('every guide page of the registry is allowed', () {
      for (final provider in registry.all) {
        final url = provider.appPasswordGuideUrl;
        if (url != null) expect(registry.isAllowedGuideLink(url), isTrue);
      }
    });

    test('only https, and only the pages of the registry', () {
      for (final bad in [
        'http://myaccount.google.com/apppasswords',
        'https://example.com/apppasswords',
        'https://myaccount.google.com.evil.example/apppasswords',
        'https://evil.example/https://myaccount.google.com/apppasswords',
        'https://myaccount.google.com/other',
        'https://user@myaccount.google.com/apppasswords',
        'https://myaccount.google.com/apppasswords?account=a@example.test',
        'https://myaccount.google.com/apppasswords#frag',
        'https://myaccount.google.com:8443/apppasswords',
        'ftp://myaccount.google.com/apppasswords',
        'file:///sdcard/x',
        'javascript:alert(1)',
        'intent://scan#Intent;scheme=https;end',
        'mailto:a@example.com',
        'myaccount.google.com/apppasswords',
        '',
        'https://',
      ]) {
        expect(registry.isAllowedGuideLink(bad), isFalse, reason: bad);
      }
    });

    test('the standard registry holds no link that carries a user', () {
      for (final provider in registry.all) {
        final url = provider.appPasswordGuideUrl;
        if (url == null) continue;
        final uri = Uri.parse(url);
        expect(uri.scheme, 'https');
        expect(uri.hasQuery, isFalse);
        expect(uri.userInfo, isEmpty);
      }
    });
  });

  group('the order of the share route', () {
    test('the app of the provider, when it is installed', () {
      final route = chooseShareRoute(
        providerPackage: 'com.google.android.gm',
        apps: const MailApps(
          providerAppInstalled: true,
          mailtoPackages: ['com.google.android.gm', 'com.example.other'],
        ),
      );
      expect((route as ProviderAppRoute).package, 'com.google.android.gm');
    });

    test('not installed, one e-mail app: that one, opened directly', () {
      final route = chooseShareRoute(
        providerPackage: 'com.microsoft.office.outlook',
        apps: const MailApps(mailtoPackages: ['com.example.mail']),
      );
      expect((route as SingleMailAppRoute).package, 'com.example.mail');
    });

    test('not installed, several e-mail apps: a chooser of them only', () {
      final route = chooseShareRoute(
        providerPackage: 'com.microsoft.office.outlook',
        apps: const MailApps(mailtoPackages: ['a.mail', 'b.mail']),
      );
      expect((route as MailAppChooserRoute).packages, ['a.mail', 'b.mail']);
    });

    test('the same package twice is one app', () {
      final route = chooseShareRoute(
        providerPackage: null,
        apps: const MailApps(mailtoPackages: ['a.mail', 'a.mail']),
      );
      expect(route, isA<SingleMailAppRoute>());
    });

    test('no e-mail app at all: the generic menu, the last resort', () {
      expect(
        chooseShareRoute(
          providerPackage: 'com.yahoo.mobile.client.android.mail',
          apps: const MailApps(),
        ),
        isA<GenericShareRoute>(),
      );
    });

    test('no provider chosen: the e-mail apps of the phone', () {
      expect(
        chooseShareRoute(
          providerPackage: null,
          apps: const MailApps(providerAppInstalled: true),
        ),
        isA<GenericShareRoute>(),
      );
    });
  });

  group(
    'ShareScanPdfDraft asks the phone and hands the route to the sharer',
    () {
      late FakeDraftSharer sharer;
      late FakeMailAppFinder finder;
      late ShareScanPdfDraft share;

      setUp(() {
        sharer = FakeDraftSharer();
        finder = FakeMailAppFinder();
        share = ShareScanPdfDraft(
          sharer: sharer,
          finder: finder,
          providers: registry,
        );
      });

      for (final (id, package) in [
        (MailProviderId.gmail, 'com.google.android.gm'),
        (MailProviderId.outlook, 'com.microsoft.office.outlook'),
        (MailProviderId.yahoo, 'com.yahoo.mobile.client.android.mail'),
      ]) {
        test('${id.name}: its app when installed', () async {
          finder.apps = const MailApps(
            providerAppInstalled: true,
            mailtoPackages: ['x.mail', 'y.mail'],
          );

          final result = await share(
            settings: settingsOf(provider: id),
            pdf: pdfOf(),
          );

          expect(result, DraftShareResult.opened);
          expect(finder.asked.single, package);
          expect((sharer.routes.single as ProviderAppRoute).package, package);
        });

        test('${id.name}: not installed, one mail app', () async {
          finder.apps = const MailApps(mailtoPackages: ['x.mail']);

          await share(
            settings: settingsOf(provider: id),
            pdf: pdfOf(),
          );

          expect(sharer.routes.single, isA<SingleMailAppRoute>());
        });

        test('${id.name}: not installed, several mail apps', () async {
          finder.apps = const MailApps(mailtoPackages: ['x.mail', 'y.mail']);

          await share(
            settings: settingsOf(provider: id),
            pdf: pdfOf(),
          );

          expect(sharer.routes.single, isA<MailAppChooserRoute>());
        });

        test('${id.name}: no mail app, the generic menu', () async {
          await share(
            settings: settingsOf(provider: id),
            pdf: pdfOf(),
          );
          expect(sharer.routes.single, isA<GenericShareRoute>());
        });
      }

      test('no provider chosen: no package is asked for', () async {
        await share(
          settings: settingsOf(provider: null, sender: null),
          pdf: pdfOf(),
        );
        expect(finder.asked.single, isNull);
      });

      test('a finder that fails is a failure, not a crash', () async {
        finder.throws = true;
        final result = await share(settings: settingsOf(), pdf: pdfOf());
        expect(result, DraftShareResult.failed);
        expect(sharer.shared, isEmpty);
      });

      test('the message is the same on every route: subject, body, recipient, '
          'document URI', () async {
        final pdf = pdfOf();
        await share(settings: settingsOf(), pdf: pdf);

        final shared = sharer.shared.single;
        expect(shared['subject'], 'One Click Scan - 2026-10-21_19-05-12');
        expect(shared['body'], 'Document scanned with One Click Scan.');
        expect(shared['to'], [testAccount]);
        expect(shared['uri'], pdf.uri);
      });
    },
  );

  group('OpenProviderGuide', () {
    test(
      'opens the page of the provider through the port, nothing added',
      () async {
        final opener = FakeLinkOpener();
        final guide = OpenProviderGuide(opener: opener, providers: registry);

        expect(await guide(MailProviderId.gmail), isTrue);
        expect(await guide(MailProviderId.yahoo), isTrue);

        expect(opener.opened, [
          'https://myaccount.google.com/apppasswords',
          'https://login.yahoo.com/account/security',
        ]);
      },
    );

    test('Outlook has no page: nothing is opened', () async {
      final opener = FakeLinkOpener();
      final guide = OpenProviderGuide(opener: opener, providers: registry);

      expect(await guide(MailProviderId.outlook), isFalse);
      expect(opener.opened, isEmpty);
    });

    test('a registry with a link that is not allowed opens nothing', () async {
      final opener = FakeLinkOpener();
      final bad = MailProviderRegistry({
        MailProviderId.gmail: const MailProvider(
          id: 'gmail',
          smtp: SmtpEndpoint(host: 'h', port: 1, security: SmtpSecurity.plain),
          authKinds: {MailAuthKind.appPassword},
          appPasswordSupport: AppPasswordSupport.supported,
          maxMessageBytes: 1,
          // Allowed by the list, but with a query: refused.
          appPasswordGuideUrl: 'https://myaccount.google.com/x?user=a',
        ),
      });
      final guide = OpenProviderGuide(opener: opener, providers: bad);

      expect(await guide(MailProviderId.gmail), isFalse);
      expect(opener.opened, isEmpty);
    });

    test('a browser that does not start is false', () async {
      final opener = FakeLinkOpener()..result = false;
      final guide = OpenProviderGuide(opener: opener, providers: registry);
      expect(await guide(MailProviderId.gmail), isFalse);
    });
  });

  group('the diagnostic of an outcome: a step and a code, nothing else', () {
    test('every outcome says its step', () {
      expect(const MailAuthFailed(code: 535).stage, MailStage.authentication);
      expect(const MailAuthFailed(code: 535).replyCode, 535);
      expect(const MailAuthFailed().replyCode, isNull);
      expect(const MailNetworkError().stage, MailStage.connection);
      expect(
        const MailNetworkError(failedStage: MailStage.tls).stage,
        MailStage.tls,
      );
      expect(const MailRejected(550).stage, MailStage.sending);
      expect(const MailRejected(550).replyCode, 550);
      expect(const MailRejected(0).replyCode, isNull);
      expect(const MailTooLarge(fromServer: true).replyCode, 552);
      expect(const MailTooLarge().stage, isNull);
      expect(const MailTooLarge().replyCode, isNull);
      expect(const MailUnknown().stage, isNull);
      expect(const MailSent().stage, isNull);
      expect(const MailCancelled().stage, isNull);
      expect(
        const MailNotConfigured(MailNotConfiguredReason.password).stage,
        isNull,
      );
    });
  });
}
