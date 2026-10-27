import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/core/config/app_config.dart';
import 'package:one_click_scan/domain/entities/destination_mode.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/mail_send_mode.dart';
import 'package:one_click_scan/domain/mail/mail_outcome.dart';
import 'package:one_click_scan/domain/mail/share_route.dart';
import 'package:one_click_scan/domain/ports/draft_sharer.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/scan/scan_keys.dart';
import 'package:one_click_scan/features/settings/settings_keys.dart';

import '../../support/fakes.dart';
import '../../support/mail_fakes.dart';
import '../../support/ocr_fakes.dart';
import '../../support/pdf_fakes.dart';
import '../../support/scan_fakes.dart';

/// Scan -> result screen -> the Send section, with real cubits and fake
/// adapters for the OCR, the PDF writer and the mail.
void main() {
  late OcrTestRig rig;
  late PdfTestRig pdf;
  late MailTestRig mail;
  late FakeScanFileStore store;

  Future<void> pumpHome(
    WidgetTester tester, {
    String language = 'en',
    MailProviderId provider = MailProviderId.gmail,
    bool withPassword = true,
    MailSendMode mode = MailSendMode.sendNow,
    DestinationMode destination = DestinationMode.own,
    String? custom,
  }) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    rig = OcrTestRig();
    pdf = PdfTestRig();
    mail = MailTestRig();
    if (withPassword) mail.storePassword(provider: provider);
    store = FakeScanFileStore();
    final values = InMemoryKeyValueStore();
    Future<GetIt> build() => buildTestContainer(
      config: AppConfig.forDeviceLanguage(language),
      store: values,
      scanFileStore: store,
      ocr: rig.services,
      pdf: pdf.services,
      mail: mail.services,
    );
    final seed = await build();
    await seed<SettingsRepository>().save(
      (await seed<SettingsRepository>().load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        mailProvider: provider,
        senderAccount: testAccount,
        mailSendMode: mode,
        destinationMode: destination,
        customDestination: custom,
      ),
    );
    await tester.pumpWidget(OneClickScanApp(container: await build()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeKeys.scanAndSend));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  testWidgets('the Send section appears once the PDF is stored and says where '
      'the PDF goes', (tester) async {
    await pumpHome(tester);

    expect(find.byKey(ScanKeys.mailSend), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
    expect(find.text('The PDF will be sent to $testAccount.'), findsOneWidget);
    expect(mail.sender.sent, isEmpty);
  });

  testWidgets('another address: the note names it', (tester) async {
    await pumpHome(
      tester,
      destination: DestinationMode.custom,
      custom: testDestination,
    );

    expect(
      find.text('The PDF will be sent to $testDestination.'),
      findsOneWidget,
    );
  });

  testWidgets('Send: the message goes, and the screen says the server took '
      'it (no promise of delivery)', (tester) async {
    await pumpHome(tester);

    await tapKey(tester, ScanKeys.mailSend);

    final sent = mail.sender.sent.single;
    expect(sent.subject, 'One Click Scan - 2026-10-21_19-05-12');
    expect(sent.attachments.single.fileName, '2026-10-21_19-05-12.pdf');
    expect(
      find.text('The message was sent from the e-mail server.'),
      findsOneWidget,
    );
    expect(find.textContaining('deliver'), findsNothing);
    expect(find.byKey(ScanKeys.mailSend), findsNothing);
  });

  testWidgets('the screen speaks Greek', (tester) async {
    await pumpHome(tester, language: 'el');

    expect(find.text('Αποστολή'), findsOneWidget);
    await tapKey(tester, ScanKeys.mailSend);
    expect(
      find.text('Το μήνυμα στάλθηκε από τον διακομιστή email.'),
      findsOneWidget,
    );
    expect(
      mail.sender.sent.single.body,
      'Σαρωμένο έγγραφο από το One Click Scan.',
    );
  });

  testWidgets('while sending: a state in words, a Cancel button, leaving is '
      'locked', (tester) async {
    await pumpHome(tester);
    mail.sender.hold = Completer<MailOutcome>();

    await tester.tap(find.byKey(ScanKeys.mailSend));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(ScanKeys.mailStatus), findsOneWidget);
    expect(find.text('Sending…'), findsWidgets);
    expect(find.byKey(ScanKeys.mailCancel), findsOneWidget);
    final back = tester.widget<FilledButton>(find.byKey(ScanKeys.resultBack));
    expect(back.onPressed, isNull);

    mail.sender.hold!.complete(const MailSent());
    await tester.pumpAndSettle();
    final backAfter = tester.widget<FilledButton>(
      find.byKey(ScanKeys.resultBack),
    );
    expect(backAfter.onPressed, isNotNull);
  });

  testWidgets('Cancel stops the send and the button comes back', (
    tester,
  ) async {
    await pumpHome(tester);
    mail.sender.hold = Completer<MailOutcome>();
    await tester.tap(find.byKey(ScanKeys.mailSend));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(ScanKeys.mailCancel));
    await tester.pumpAndSettle();

    expect(find.byKey(ScanKeys.mailSend), findsOneWidget);
    expect(find.byKey(ScanKeys.mailFailure), findsNothing);
  });

  group('a failure says why, in words the user understands', () {
    final cases = <String, (MailOutcome, String)>{
      'auth': (
        const MailAuthFailed(),
        'The server did not accept the account or the password. With MFA '
            '(2-step verification) on, an app password made at the provider is '
            'needed, not the normal password of the account. For some accounts '
            '(for example work or school accounts) the administrator does not '
            'allow app passwords.',
      ),
      'network': (
        const MailNetworkError(),
        'Could not connect to the e-mail server. Check the internet and try '
            'again.',
      ),
      'too large': (
        const MailTooLarge(),
        'The PDF is too big to send by e-mail through this provider. Open it in '
            'the e-mail app or share it another way.',
      ),
      'rejected': (
        const MailRejected(550),
        'The e-mail server rejected the message.',
      ),
      'unknown': (
        const MailUnknown(),
        'The message was not sent because of an unexpected error.',
      ),
    };
    for (final entry in cases.entries) {
      testWidgets(entry.key, (tester) async {
        await pumpHome(tester);
        mail.sender.outcome = entry.value.$1;

        await tapKey(tester, ScanKeys.mailSend);

        expect(find.text(entry.value.$2), findsOneWidget);
        expect(find.byKey(ScanKeys.mailRetry), findsOneWidget);
        expect(find.byKey(ScanKeys.mailOpenApp), findsOneWidget);
      });
    }
  });

  testWidgets('Try again sends again, and can succeed', (tester) async {
    await pumpHome(tester);
    mail.sender.outcome = const MailNetworkError();
    await tapKey(tester, ScanKeys.mailSend);

    mail.sender.outcome = const MailSent();
    await tapKey(tester, ScanKeys.mailRetry);

    expect(mail.sender.sent, hasLength(2));
    expect(
      find.text('The message was sent from the e-mail server.'),
      findsOneWidget,
    );
  });

  testWidgets('Outlook: a refused password adds the warning and the way out', (
    tester,
  ) async {
    await pumpHome(tester, provider: MailProviderId.outlook);
    mail.sender.outcome = const MailAuthFailed();

    await tapKey(tester, ScanKeys.mailSend);

    expect(
      find.textContaining('does not yet accept sending from the app'),
      findsOneWidget,
    );
    expect(find.byKey(ScanKeys.mailOpenApp), findsOneWidget);
    expect(find.byKey(ScanKeys.mailFallback), findsOneWidget);
  });

  group('the diagnostic line: the step and the code, nothing else', () {
    final cases = <String, (MailOutcome, String)>{
      'auth 535': (
        const MailAuthFailed(code: 535),
        'Step: authentication, code 535',
      ),
      'auth, no code': (const MailAuthFailed(), 'Step: authentication'),
      'network': (const MailNetworkError(), 'Step: connection'),
      'tls': (const MailNetworkError(failedStage: MailStage.tls), 'Step: TLS'),
      'rejected': (const MailRejected(550), 'Step: sending, code 550'),
      'rejected without a code': (const MailRejected(0), 'Step: sending'),
      'too large from the server': (
        const MailTooLarge(fromServer: true),
        'Step: sending, code 552',
      ),
    };
    for (final entry in cases.entries) {
      testWidgets(entry.key, (tester) async {
        await pumpHome(tester);
        mail.sender.outcome = entry.value.$1;

        await tapKey(tester, ScanKeys.mailSend);

        expect(
          tester.widget<Text>(find.byKey(ScanKeys.mailDiagnostic)).data,
          entry.value.$2,
        );
      });
    }

    testWidgets('no line without a step (too large before sending, unknown)', (
      tester,
    ) async {
      await pumpHome(tester);
      mail.sender.outcome = const MailTooLarge();
      await tapKey(tester, ScanKeys.mailSend);
      expect(find.byKey(ScanKeys.mailDiagnostic), findsNothing);

      mail.sender.outcome = const MailUnknown();
      await tapKey(tester, ScanKeys.mailRetry);
      expect(find.byKey(ScanKeys.mailDiagnostic), findsNothing);
    });

    testWidgets('the screen shows neither the password nor the address in '
        'the failure', (tester) async {
      await pumpHome(tester);
      mail.sender.outcome = const MailAuthFailed(code: 535);

      await tapKey(tester, ScanKeys.mailSend);

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');
      expect(texts, isNot(contains(canarySecret)));
      expect(texts, isNot(contains(testAccount)));
    });

    testWidgets('in Greek', (tester) async {
      await pumpHome(tester, language: 'el');
      mail.sender.outcome = const MailAuthFailed(code: 535);

      await tapKey(tester, ScanKeys.mailSend);

      expect(
        tester.widget<Text>(find.byKey(ScanKeys.mailDiagnostic)).data,
        'Στάδιο: ταυτοποίηση, κωδικός 535',
      );
    });
  });

  group('the one-tap backup way', () {
    testWidgets('a refused sign-in offers it, with the reason; one tap sets '
        'the mode and the button now opens the e-mail app', (tester) async {
      await pumpHome(tester);
      mail.sender.outcome = const MailAuthFailed(code: 535);
      await tapKey(tester, ScanKeys.mailSend);

      expect(find.byKey(ScanKeys.mailFallback), findsOneWidget);
      expect(
        find.textContaining('did not accept an app password'),
        findsOneWidget,
      );

      await tapKey(tester, ScanKeys.mailFallback);

      expect(find.byKey(ScanKeys.mailFallback), findsNothing);
      expect(find.byKey(ScanKeys.mailFailure), findsNothing);
      expect(find.text('Open in the e-mail app'), findsOneWidget);
    });

    testWidgets('the mode is stored: the next tap opens the mail app', (
      tester,
    ) async {
      await pumpHome(tester);
      mail.sender.outcome = const MailAuthFailed(code: 535);
      await tapKey(tester, ScanKeys.mailSend);
      await tapKey(tester, ScanKeys.mailFallback);

      await tapKey(tester, ScanKeys.mailSend);

      expect(mail.sharer.shared, hasLength(1));
      expect(mail.sender.sent, hasLength(1)); // only the first, failed try
    });

    testWidgets('a network failure does not offer it (Gmail)', (tester) async {
      await pumpHome(tester);
      mail.sender.outcome = const MailNetworkError();
      await tapKey(tester, ScanKeys.mailSend);
      expect(find.byKey(ScanKeys.mailFallback), findsNothing);
    });

    testWidgets('Outlook offers it for any failure, with its own reason', (
      tester,
    ) async {
      await pumpHome(tester, provider: MailProviderId.outlook);
      mail.sender.outcome = const MailNetworkError();
      await tapKey(tester, ScanKeys.mailSend);

      expect(find.byKey(ScanKeys.mailFallback), findsOneWidget);
      expect(
        find.textContaining(
          'does not yet support sending with an app password',
        ),
        findsOneWidget,
      );
    });

    testWidgets('already in the share mode: not offered', (tester) async {
      await pumpHome(tester, mode: MailSendMode.shareDraft);
      mail.sharer.result = DraftShareResult.failed;
      await tapKey(tester, ScanKeys.mailSend);
      expect(find.byKey(ScanKeys.mailFallback), findsNothing);
    });

    testWidgets('a refused sign-in also leads to the guide in Settings', (
      tester,
    ) async {
      await pumpHome(tester);
      mail.sender.outcome = const MailAuthFailed(code: 535);
      await tapKey(tester, ScanKeys.mailSend);

      await tapKey(tester, ScanKeys.mailGuide);

      // The settings screen is open, where the guide is.
      expect(find.byKey(SettingsKeys.password), findsOneWidget);
    });

    testWidgets('the guide link is not offered for Outlook (no steps)', (
      tester,
    ) async {
      await pumpHome(tester, provider: MailProviderId.outlook);
      mail.sender.outcome = const MailAuthFailed(code: 535);
      await tapKey(tester, ScanKeys.mailSend);
      expect(find.byKey(ScanKeys.mailGuide), findsNothing);
    });
  });

  testWidgets('Open in the e-mail app after a failure hands the PDF to the '
      'mail app and says the user presses send there', (tester) async {
    await pumpHome(tester);
    mail.sender.outcome = const MailNetworkError();
    await tapKey(tester, ScanKeys.mailSend);

    await tapKey(tester, ScanKeys.mailOpenApp);

    final shared = mail.sharer.shared.single;
    expect(shared['subject'], 'One Click Scan - 2026-10-21_19-05-12');
    expect(shared['uri'], contains('2026-10-21_19-05-12.pdf'));
    expect(find.byKey(ScanKeys.mailDraft), findsOneWidget);
    expect(find.textContaining('Press send there'), findsOneWidget);
  });

  testWidgets('no mail app: a clear message', (tester) async {
    await pumpHome(tester);
    mail.sender.outcome = const MailNetworkError();
    mail.sharer.result = DraftShareResult.noApp;
    await tapKey(tester, ScanKeys.mailSend);

    await tapKey(tester, ScanKeys.mailOpenApp);

    expect(
      find.text('No e-mail app that takes an attachment was found.'),
      findsOneWidget,
    );
  });

  testWidgets('only the generic menu opened: it says no e-mail app was found', (
    tester,
  ) async {
    await pumpHome(tester);
    mail.sender.outcome = const MailNetworkError();
    mail.sharer.result = DraftShareResult.openedGeneric;
    await tapKey(tester, ScanKeys.mailSend);

    await tapKey(tester, ScanKeys.mailOpenApp);

    expect(find.textContaining('generic share menu opened'), findsOneWidget);
  });

  testWidgets('the route asked for is the one of the phone: the app of the '
      'provider first', (tester) async {
    await pumpHome(tester, mode: MailSendMode.shareDraft, withPassword: false);
    mail.appFinder.apps = const MailApps(
      providerAppInstalled: true,
      mailtoPackages: ['com.example.other'],
    );

    await tapKey(tester, ScanKeys.mailSend);

    expect(mail.appFinder.asked.single, 'com.google.android.gm');
    expect(
      (mail.sharer.routes.single as ProviderAppRoute).package,
      'com.google.android.gm',
    );
  });

  testWidgets('no password: the screen leads to the settings, nothing is '
      'tried', (tester) async {
    await pumpHome(tester, withPassword: false);

    await tapKey(tester, ScanKeys.mailSend);

    expect(
      find.text(
        'No app password is stored for this account. Enter it in Settings.',
      ),
      findsOneWidget,
    );
    expect(mail.sender.sent, isEmpty);
    expect(find.byKey(ScanKeys.mailRetry), findsNothing);

    await tapKey(tester, ScanKeys.mailOpenSettings);
    expect(find.byKey(SettingsKeys.password), findsOneWidget);
  });

  testWidgets('the share mode: the button opens the mail app and the note '
      'says who presses send', (tester) async {
    await pumpHome(tester, mode: MailSendMode.shareDraft, withPassword: false);

    expect(find.byKey(ScanKeys.mailNote), findsOneWidget);
    expect(
      find.textContaining('leaves when you press send there'),
      findsOneWidget,
    );
    expect(find.text('Open in the e-mail app'), findsOneWidget);

    await tapKey(tester, ScanKeys.mailSend);

    expect(mail.sender.sent, isEmpty);
    expect(mail.sharer.shared, hasLength(1));
    expect(find.textContaining('Press send there'), findsOneWidget);
  });
}
