import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/core/config/app_config.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/mail_send_mode.dart';
import 'package:one_click_scan/domain/mail/mail_outcome.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/settings/settings_keys.dart';

import '../../support/fakes.dart';
import '../../support/mail_fakes.dart';

void main() {
  late MailTestRig mail;
  late SettingsRepository repository;

  Future<void> pumpSettings(
    WidgetTester tester, {
    MailProviderId provider = MailProviderId.gmail,
    bool stored = false,
    String language = 'en',
    MailSendMode mode = MailSendMode.sendNow,
  }) async {
    tester.view.physicalSize = const Size(800, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    mail = MailTestRig();
    if (stored) mail.storePassword(provider: provider);
    final values = InMemoryKeyValueStore();
    Future<GetIt> build() => buildTestContainer(
      config: AppConfig.forDeviceLanguage(language),
      store: values,
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
      ),
    );
    final container = await build();
    repository = container<SettingsRepository>();
    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeKeys.settings));
    await tester.pumpAndSettle();
  }

  TextField passwordField(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(SettingsKeys.password));

  Future<void> enterPassword(WidgetTester tester, String value) async {
    await tester.enterText(find.byKey(SettingsKeys.password), value);
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  testWidgets('the password field is hidden, and a button shows it', (
    tester,
  ) async {
    await pumpSettings(tester);

    expect(passwordField(tester).obscureText, isTrue);
    await tapKey(tester, SettingsKeys.passwordToggle);
    expect(passwordField(tester).obscureText, isFalse);
    await tapKey(tester, SettingsKeys.passwordToggle);
    expect(passwordField(tester).obscureText, isTrue);
  });

  testWidgets('the field does not suggest or correct what is typed', (
    tester,
  ) async {
    await pumpSettings(tester);

    final field = passwordField(tester);
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
  });

  testWidgets('the status says whether a password is stored, and where', (
    tester,
  ) async {
    await pumpSettings(tester);
    expect(find.text('No password is stored.'), findsOneWidget);
    expect(find.textContaining('Android Keystore'), findsOneWidget);
    expect(find.byKey(SettingsKeys.passwordDelete), findsNothing);
  });

  testWidgets('a stored password shows the delete button, which removes it', (
    tester,
  ) async {
    await pumpSettings(tester, stored: true);
    expect(find.text('A password is stored on this phone.'), findsOneWidget);

    await tapKey(tester, SettingsKeys.passwordDelete);

    expect(mail.credentials.stored, isNull);
    expect(find.text('No password is stored.'), findsOneWidget);
    expect(find.byKey(SettingsKeys.passwordDelete), findsNothing);
    expect(find.text('The password was deleted.'), findsOneWidget);
  });

  testWidgets('Save with a typed password stores it and clears the field', (
    tester,
  ) async {
    await pumpSettings(tester);
    await enterPassword(tester, canarySecret);

    await tapKey(tester, SettingsKeys.save);

    expect(mail.credentials.stored!.secret, canarySecret);
    expect(passwordField(tester).controller!.text, isEmpty);
    expect(find.text('A password is stored on this phone.'), findsOneWidget);
  });

  testWidgets('the guide is open while no password is stored: what it is, '
      'the steps, the reminder, the Gmail prerequisites', (tester) async {
    await pumpSettings(tester);

    expect(find.textContaining('not the normal password'), findsOneWidget);
    expect(
      find.textContaining('1. Make sure your Google Account has 2-Step'),
      findsOneWidget,
    );
    expect(find.textContaining('4. Copy the password'), findsOneWidget);
    expect(find.textContaining('shown only once'), findsOneWidget);
    expect(find.textContaining('without spaces'), findsWidgets);
    expect(find.textContaining('administrator may forbid'), findsOneWidget);
    expect(find.byKey(SettingsKeys.guideOpen), findsOneWidget);
    expect(find.byKey(SettingsKeys.guideOutlook), findsNothing);
    // No menu name of Google that could not be read on an official page.
    expect(find.textContaining('Security >'), findsNothing);
  });

  testWidgets('with a stored password the guide is folded, and opens on tap', (
    tester,
  ) async {
    await pumpSettings(tester, stored: true);
    expect(find.textContaining('4. Copy the password'), findsNothing);

    await tapKey(tester, SettingsKeys.help);

    expect(find.textContaining('4. Copy the password'), findsOneWidget);
  });

  testWidgets('the button opens the official page of the provider, and only '
      'that', (tester) async {
    await pumpSettings(tester);

    await tapKey(tester, SettingsKeys.guideOpen);

    expect(mail.links.opened, ['https://myaccount.google.com/apppasswords']);
  });

  testWidgets('Yahoo: its steps with the names of the Yahoo page, its page, '
      'and the assumption about size', (tester) async {
    await pumpSettings(tester, provider: MailProviderId.yahoo);

    expect(find.textContaining('External connections'), findsOneWidget);
    expect(find.textContaining('Create app password'), findsOneWidget);
    expect(find.textContaining('Generate password'), findsOneWidget);
    expect(
      find.textContaining('assumes a message up to 20 MB'),
      findsOneWidget,
    );

    await tapKey(tester, SettingsKeys.guideOpen);
    expect(mail.links.opened, ['https://login.yahoo.com/account/security']);
  });

  testWidgets('a browser that did not open is said, not hidden', (
    tester,
  ) async {
    await pumpSettings(tester);
    mail.links.result = false;

    await tapKey(tester, SettingsKeys.guideOpen);

    expect(find.byKey(SettingsKeys.guideOpenFailed), findsOneWidget);
  });

  testWidgets('the steps are in Greek too', (tester) async {
    await pumpSettings(tester, language: 'el');

    expect(
      find.textContaining('1. Βεβαιώσου ότι ο λογαριασμός Google'),
      findsOneWidget,
    );
    expect(find.text('Άνοιγμα σελίδας του παρόχου'), findsOneWidget);
  });

  testWidgets('Outlook: no app password steps and no page button, a short '
      'text, and the backup way offered at once', (tester) async {
    await pumpSettings(tester, provider: MailProviderId.outlook);

    expect(find.byKey(SettingsKeys.guideOutlook), findsOneWidget);
    expect(find.textContaining('after OAuth is built'), findsWidgets);
    expect(find.textContaining('1. '), findsNothing);
    expect(find.byKey(SettingsKeys.guideOpen), findsNothing);
    expect(find.byKey(SettingsKeys.providerWarning), findsOneWidget);
    expect(find.byKey(SettingsKeys.fallback), findsOneWidget);

    await tapKey(tester, SettingsKeys.fallback);

    expect((await repository.load()).mailSendMode, MailSendMode.shareDraft);
    expect(find.byKey(SettingsKeys.fallback), findsNothing);
  });

  testWidgets('Gmail and Yahoo show no such warning', (tester) async {
    await pumpSettings(tester);
    expect(find.byKey(SettingsKeys.providerWarning), findsNothing);
  });

  group('the connection test button', () {
    testWidgets('success: said in words, nothing was sent', (tester) async {
      await pumpSettings(tester);
      await enterPassword(tester, canarySecret);

      await tapKey(tester, SettingsKeys.mailTest);

      expect(
        find.text('The server accepted the account. No message was sent.'),
        findsOneWidget,
      );
      expect(mail.sender.sent, isEmpty);
      expect(mail.sender.checks, 1);
    });

    testWidgets('no password: it asks for one', (tester) async {
      await pumpSettings(tester);

      await tapKey(tester, SettingsKeys.mailTest);

      expect(
        find.text('Enter the app password first (or save it).'),
        findsOneWidget,
      );
      expect(mail.sender.checks, 0);
    });

    testWidgets('a refused password and a missing connection have their '
        'own messages', (tester) async {
      await pumpSettings(tester);
      await enterPassword(tester, canarySecret);

      mail.sender.outcome = const MailAuthFailed();
      await tapKey(tester, SettingsKeys.mailTest);
      expect(find.textContaining('did not accept the account'), findsOneWidget);

      mail.sender.outcome = const MailNetworkError();
      await tapKey(tester, SettingsKeys.mailTest);
      expect(find.textContaining('Could not connect'), findsOneWidget);
    });

    testWidgets('a failure carries the diagnostic line: step and code, and '
        'no address, host or password', (tester) async {
      await pumpSettings(tester);
      await enterPassword(tester, canarySecret);
      mail.sender.outcome = const MailAuthFailed(code: 535);

      await tapKey(tester, SettingsKeys.mailTest);

      final text = tester
          .widget<Text>(find.byKey(SettingsKeys.mailTestResult))
          .data!;
      expect(text, endsWith('Step: authentication, code 535'));
      expect(text, isNot(contains(canarySecret)));
      expect(text, isNot(contains(testAccount)));
      expect(text, isNot(contains('smtp')));
    });

    testWidgets('a refused sign-in offers the backup way with one tap; other '
        'failures do not', (tester) async {
      await pumpSettings(tester);
      await enterPassword(tester, canarySecret);

      mail.sender.outcome = const MailNetworkError();
      await tapKey(tester, SettingsKeys.mailTest);
      expect(find.byKey(SettingsKeys.fallback), findsNothing);

      mail.sender.outcome = const MailAuthFailed(code: 535);
      await tapKey(tester, SettingsKeys.mailTest);
      expect(find.byKey(SettingsKeys.fallback), findsOneWidget);
      expect(
        find.textContaining('did not accept an app password'),
        findsOneWidget,
      );

      await tapKey(tester, SettingsKeys.fallback);
      expect((await repository.load()).mailSendMode, MailSendMode.shareDraft);
      expect(find.byKey(SettingsKeys.fallback), findsNothing);
    });

    testWidgets('already in the share mode: the backup way is not offered', (
      tester,
    ) async {
      await pumpSettings(tester, mode: MailSendMode.shareDraft);
      await enterPassword(tester, canarySecret);
      mail.sender.outcome = const MailAuthFailed(code: 535);

      await tapKey(tester, SettingsKeys.mailTest);

      expect(find.byKey(SettingsKeys.fallback), findsNothing);
    });

    testWidgets('the password is not shown in the result or anywhere in the '
        'text of the screen', (tester) async {
      await pumpSettings(tester);
      await enterPassword(tester, canarySecret);
      await tapKey(tester, SettingsKeys.mailTest);

      // The typed text sits only in the (hidden) field, in no Text widget.
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').contains(canarySecret),
        ),
        findsNothing,
      );
    });
  });

  testWidgets('the way to send is saved at once', (tester) async {
    await pumpSettings(tester);

    await tester.ensureVisible(find.byKey(SettingsKeys.sendMode));
    await tester.tap(find.text('Open in the e-mail app').last);
    await tester.pumpAndSettle();

    expect((await repository.load()).mailSendMode, MailSendMode.shareDraft);
  });
}
