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
        'The server did not accept the account or the password. Check the app '
            'password in Settings.',
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
        'The e-mail server rejected the message (code 550).',
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

    expect(find.textContaining('modern sign-in (OAuth)'), findsOneWidget);
    expect(find.byKey(ScanKeys.mailOpenApp), findsOneWidget);
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
