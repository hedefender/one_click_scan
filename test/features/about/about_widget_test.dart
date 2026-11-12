import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/core/config/about_config.dart';
import 'package:one_click_scan/core/config/app_config.dart';
import 'package:one_click_scan/core/config/feedback_config.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/ports/app_info_source.dart';
import 'package:one_click_scan/domain/ports/feedback_composer.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/about/about_keys.dart';
import 'package:one_click_scan/features/about/about_page.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/settings/settings_keys.dart';
import 'package:one_click_scan/presentation/l10n/app_strings.dart';
import 'package:one_click_scan/presentation/l10n/app_strings_el.dart';
import 'package:one_click_scan/presentation/l10n/app_strings_en.dart';
import 'package:one_click_scan/services/about/about_services.dart';

import '../../support/fakes.dart';
import '../../support/mail_fakes.dart';

class _FakeInfo implements AppInfoSource {
  @override
  Future<AppInfo?> read() async => const AppInfo(
    versionName: '0.1.0',
    buildNumber: '7',
    androidRelease: '14',
  );
}

class _FakeFeedback implements FeedbackComposer {
  bool result = true;
  final calls = <({String to, String subject, String body})>[];

  @override
  Future<bool> compose({
    required String to,
    required String subject,
    required String body,
  }) async {
    calls.add((to: to, subject: subject, body: body));
    return result;
  }
}

/// Phase 6.5: About in Settings, the privacy note and the feedback button.
void main() {
  final links = FakeLinkOpener();
  final feedback = _FakeFeedback();

  setUp(() {
    links
      ..result = true
      ..opened.clear();
    feedback
      ..result = true
      ..calls.clear();
  });

  Future<void> pumpAbout(
    WidgetTester tester, {
    String language = 'en',
    String recipient = 'feedback@example.com',
    double textScale = 1.0,
    bool smallPhone = false,
  }) async {
    if (smallPhone) {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 3; // 360 x 640 dp
    } else {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
    }
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: AboutPage(
          appName: 'One Click Scan',
          infoSource: _FakeInfo(),
          links: links,
          feedback: feedback,
          feedbackRecipient: recipient,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the facts on the screen', () {
    testWidgets('name, version and build, description, copyright, link', (
      tester,
    ) async {
      await pumpAbout(tester);

      expect(find.text('One Click Scan'), findsOneWidget);
      expect(find.text('Version 0.1.0 (build 7)'), findsOneWidget);
      expect(find.textContaining('Scan a document'), findsOneWidget);
      expect(find.text(AboutConfig.copyright), findsOneWidget);
      expect(find.text(AboutConfig.repositoryUrl), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('Greek', (tester) async {
      await pumpAbout(tester, language: 'el');

      expect(find.text('Έκδοση 0.1.0 (build 7)'), findsOneWidget);
      expect(find.text('Ιδιωτικότητα'), findsOneWidget);
    });

    testWidgets('the repository button opens only the repository page', (
      tester,
    ) async {
      await pumpAbout(tester);
      await tester.tap(find.byKey(AboutKeys.openRepo));
      await tester.pumpAndSettle();

      expect(links.opened, [AboutConfig.repositoryUrl]);
      expect(AboutConfig.repositoryUrl, startsWith('https://'));
    });

    testWidgets('no browser: a note, the text can still be copied', (
      tester,
    ) async {
      links.result = false;
      await pumpAbout(tester);
      await tester.tap(find.byKey(AboutKeys.openRepo));
      await tester.pump();

      expect(find.textContaining('No browser opened'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('the privacy note is shown, line by line', (tester) async {
      await pumpAbout(tester);

      for (final line in const AppStringsEn().aboutPrivacyLines) {
        expect(find.text(line), findsOneWidget);
      }
    });

    test('the privacy note keeps to what the app does', () {
      for (final lines in [
        const AppStringsEn().aboutPrivacyLines,
        const AppStringsEl().aboutPrivacyLines,
      ]) {
        expect(lines, hasLength(5));
      }
      // Nothing in the note is a promise about the future.
      final all = [
        ...const AppStringsEn().aboutPrivacyLines,
        ...const AppStringsEl().aboutPrivacyLines,
      ].join(' ').toLowerCase();
      for (final word in ['will ', 'never', 'guarantee', 'ποτέ', 'θα ']) {
        expect(all, isNot(contains(word)), reason: word);
      }
    });
  });

  group('the feedback button', () {
    test('the recipient is empty until the owner fills it in', () {
      expect(FeedbackConfig.recipient, isEmpty);
    });

    testWidgets('with no recipient it is not shown', (tester) async {
      await pumpAbout(tester, recipient: '');

      expect(find.byKey(AboutKeys.feedback), findsNothing);
      expect(find.text('Send feedback'), findsNothing);
    });

    testWidgets('with a recipient it opens the e-mail with the message', (
      tester,
    ) async {
      await pumpAbout(tester);
      await tester.tap(find.byKey(AboutKeys.feedback));
      await tester.pumpAndSettle();

      expect(feedback.calls, hasLength(1));
      final call = feedback.calls.single;
      expect(call.to, 'feedback@example.com');
      expect(call.subject, 'One Click Scan 0.1.0 (7)');
      expect(call.body, contains('What did you do?'));
      expect(call.body, contains('What did you expect?'));
      expect(call.body, contains('What happened?'));
      expect(call.body, contains('App version: 0.1.0 (7)'));
      expect(call.body, contains('Android version: 14'));
      expect(call.body, contains('Language: en'));
    });

    testWidgets('Greek message, and nothing but the three technical lines', (
      tester,
    ) async {
      await pumpAbout(tester, language: 'el');
      await tester.tap(find.byKey(AboutKeys.feedback));
      await tester.pumpAndSettle();

      final body = feedback.calls.single.body;
      expect(body, contains('Τι έκανες;'));
      expect(body, contains('Τι περίμενες;'));
      expect(body, contains('Τι έγινε;'));
      expect(body, contains('Γλώσσα: el'));
      // After the separator there are exactly three lines of facts.
      final facts = body.split('---\n').last.trim().split('\n');
      expect(facts, hasLength(3));
    });

    test('the message holds nothing personal', () {
      for (final strings in [const AppStringsEn(), const AppStringsEl()]) {
        final text =
            '${strings.feedbackSubject('One Click Scan', '0.1.0 (7)')}\n'
            '${strings.feedbackBody(version: '0.1.0 (7)', androidRelease: '14', language: 'en')}';
        expect(text, isNot(contains('@')));
        expect(text, isNot(contains('/')));
        expect(text.toLowerCase(), isNot(contains('password')));
        expect(text, isNot(contains('κωδικ')));
      }
    });

    testWidgets('no e-mail app: a note instead of silence', (tester) async {
      feedback.result = false;
      await pumpAbout(tester);
      await tester.tap(find.byKey(AboutKeys.feedback));
      await tester.pump();

      expect(find.textContaining('No e-mail app was found'), findsOneWidget);
    });
  });

  group('the native side, as the channel sees it', () {
    const channel = MethodChannel(aboutChannelName);

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'appInfo is read as numbers; a failure is null, never a throw',
      () async {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'appInfo');
          return <String, Object?>{
            'versionName': '0.1.0',
            'buildNumber': '7',
            'androidRelease': '14',
          };
        });
        final info = await AndroidAppInfoSource().read();
        expect(info?.versionLabel, '0.1.0 (7)');
        expect(info?.androidRelease, '14');

        messenger.setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'x');
        });
        expect(await AndroidAppInfoSource().read(), isNull);
      },
    );

    test('composeMail sends only to, subject and body', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Object? seen;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'composeMail');
        seen = call.arguments;
        return 'opened';
      });
      final opened = await AndroidFeedbackComposer().compose(
        to: 'feedback@example.com',
        subject: 's',
        body: 'b',
      );
      expect(opened, isTrue);
      expect((seen as Map).keys.toSet(), {'to', 'subject', 'body'});

      messenger.setMockMethodCallHandler(channel, (call) async => 'no_app');
      expect(
        await AndroidFeedbackComposer().compose(
          to: 'a@example.com',
          subject: '',
          body: '',
        ),
        isFalse,
      );
    });
  });

  group('inside Settings', () {
    testWidgets('the entry is in Settings and opens About', (tester) async {
      tester.view.physicalSize = const Size(800, 4200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final values = InMemoryKeyValueStore();
      Future<GetIt> build() => buildTestContainer(
        config: AppConfig.forDeviceLanguage('en'),
        store: values,
      );
      final seed = await build();
      await seed<SettingsRepository>().save(
        (await seed<SettingsRepository>().load()).copyWith(
          firstRunCompleted: true,
          storageFolder: testFolder,
          mailProvider: MailProviderId.gmail,
          senderAccount: testAccount,
        ),
      );
      await tester.pumpWidget(OneClickScanApp(container: await build()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(HomeKeys.settings));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(SettingsKeys.aboutEntry),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(SettingsKeys.aboutEntry));
      await tester.pumpAndSettle();

      expect(find.byKey(AboutKeys.page), findsOneWidget);
      // The default recipient is empty: no feedback button in this build.
      expect(find.byKey(AboutKeys.feedback), findsNothing);
    });
  });

  for (final language in ['el', 'en']) {
    testWidgets('no overflow at 360 x 640, text x1.3 ($language)', (
      tester,
    ) async {
      await pumpAbout(
        tester,
        language: language,
        textScale: 1.3,
        smallPhone: true,
      );
      expect(tester.takeException(), isNull);
      final scrollable = find.byType(Scrollable).first;
      for (var i = 0; i < 20; i++) {
        await tester.drag(scrollable, const Offset(0, -240));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'scroll step $i');
      }
      // The feedback button is at the end and can be reached.
      expect(find.byKey(AboutKeys.feedback), findsOneWidget);
    });
  }
}
