import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/domain/entities/app_settings.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/scan_flow_mode.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/first_run/first_run_keys.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/scan/scan_keys.dart';

import '../../support/fakes.dart';

void main() {
  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(find.byKey(FirstRunKeys.next));
    await tester.pumpAndSettle();
  }

  testWidgets('first launch shows the wizard, not home', (tester) async {
    final container = await buildTestContainer();
    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();

    expect(find.text('Step 1 of 5'), findsOneWidget);
    expect(find.byKey(HomeKeys.scanAndSend), findsNothing);
  });

  testWidgets('language switch re-renders the wizard in Greek', (tester) async {
    final container = await buildTestContainer();
    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ελληνικά'));
    await tester.pumpAndSettle();

    expect(find.text('Βήμα 1 από 5'), findsOneWidget);
    expect(find.text('Επόμενο'), findsOneWidget);
  });

  testWidgets('validation blocks the folder and mail steps', (tester) async {
    final container = await buildTestContainer();
    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();

    await tapNext(tester); // welcome -> folder
    await tapNext(tester); // no folder chosen
    expect(find.text('Choose a folder to continue.'), findsOneWidget);
    expect(find.text('Step 2 of 5'), findsOneWidget);

    await tester.tap(find.byKey(FirstRunKeys.pickFolder));
    await tester.pumpAndSettle();
    expect(find.text('Selected folder: Scans'), findsOneWidget);

    await tapNext(tester); // folder -> mail
    await tapNext(tester); // nothing filled in
    expect(find.text('Choose a provider.'), findsOneWidget);
    expect(find.text('Invalid email address.'), findsOneWidget);
    expect(find.text('Step 3 of 5'), findsOneWidget);
  });

  testWidgets('completing the wizard stores settings and opens home', (
    tester,
  ) async {
    final container = await buildTestContainer();
    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();

    await tapNext(tester); // welcome
    await tester.tap(find.byKey(FirstRunKeys.pickFolder));
    await tester.pumpAndSettle();
    await tapNext(tester); // folder

    await tester.tap(find.text('Gmail'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(FirstRunKeys.sender),
      'sender@example.com',
    );
    await tester.pumpAndSettle();
    await tapNext(tester); // mail

    await tapNext(tester); // gallery
    expect(find.text('Finish'), findsOneWidget);
    await tester.tap(find.byKey(FirstRunKeys.flowPreview));
    await tester.pumpAndSettle();
    await tapNext(tester); // flow -> finish

    expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);
    expect(find.text('SCAN & SEND'), findsOneWidget);
    expect(find.text('sender@example.com'), findsOneWidget);

    final AppSettings saved = await container<SettingsRepository>().load();
    expect(saved.firstRunCompleted, isTrue);
    expect(saved.mailProvider, MailProviderId.gmail);
    expect(saved.storageFolder, testFolder);
    expect(saved.saveToGallery, isFalse);
    expect(saved.scanFlowMode, ScanFlowMode.preview);
  });

  group('the One Click step', () {
    Future<GetIt> toFlowStep(WidgetTester tester) async {
      final container = await buildTestContainer();
      await tester.pumpWidget(OneClickScanApp(container: container));
      await tester.pumpAndSettle();
      await tapNext(tester); // welcome
      await tester.tap(find.byKey(FirstRunKeys.pickFolder));
      await tester.pumpAndSettle();
      await tapNext(tester); // folder
      await tester.tap(find.text('Gmail'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(FirstRunKeys.sender),
        'sender@example.com',
      );
      await tester.pumpAndSettle();
      await tapNext(tester); // mail
      await tapNext(tester); // gallery
      return container;
    }

    FilledButton nextButton(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byKey(FirstRunKeys.next));

    testWidgets('has no default: nothing is selected and Next is disabled', (
      tester,
    ) async {
      await toFlowStep(tester);

      expect(find.text('Step 5 of 5'), findsOneWidget);
      expect(find.text('One Click (no preview)'), findsOneWidget);
      expect(find.text('With preview'), findsOneWidget);
      expect(find.byKey(FirstRunKeys.flowError), findsOneWidget);
      expect(nextButton(tester).onPressed, isNull);
      final group = tester.widget<RadioGroup<ScanFlowMode>>(
        find.byType(RadioGroup<ScanFlowMode>),
      );
      expect(group.groupValue, isNull);
    });

    testWidgets('the explanation says there is no preview in One Click', (
      tester,
    ) async {
      await toFlowStep(tester);

      expect(find.textContaining('There is no preview'), findsOneWidget);
      expect(find.textContaining('send or discard'), findsWidgets);
    });

    testWidgets('One Click is stored when chosen', (tester) async {
      final container = await toFlowStep(tester);

      await tester.tap(find.byKey(FirstRunKeys.flowOneClick));
      await tester.pumpAndSettle();
      expect(nextButton(tester).onPressed, isNotNull);
      await tapNext(tester);

      final saved = await container<SettingsRepository>().load();
      expect(saved.scanFlowMode, ScanFlowMode.oneClick);
      expect(saved.firstRunCompleted, isTrue);
      expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);
    });

    testWidgets('the preview is stored when chosen', (tester) async {
      final container = await toFlowStep(tester);

      await tester.tap(find.byKey(FirstRunKeys.flowPreview));
      await tester.pumpAndSettle();
      await tapNext(tester);

      final saved = await container<SettingsRepository>().load();
      expect(saved.scanFlowMode, ScanFlowMode.preview);
      expect(saved.firstRunCompleted, isTrue);
    });

    testWidgets('the wizard is not complete before the choice', (tester) async {
      final container = await toFlowStep(tester);

      final saved = await container<SettingsRepository>().load();
      expect(saved.firstRunCompleted, isFalse);
      expect(saved.scanFlowMode, isNull);
    });
  });

  testWidgets('second launch goes straight to home', (tester) async {
    final store = InMemoryKeyValueStore();
    final first = await buildTestContainer(store: store);
    // Simulate a finished wizard by writing through the repository.
    await first<SettingsRepository>().save(
      (await first<SettingsRepository>().load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        mailProvider: MailProviderId.yahoo,
        senderAccount: 'sender@example.com',
      ),
    );

    final second = await buildTestContainer(store: store);
    await tester.pumpWidget(OneClickScanApp(container: second));
    await tester.pumpAndSettle();

    expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);
    expect(find.text('Yahoo'), findsOneWidget);
  });

  testWidgets('SCAN & SEND opens the camera screen', (tester) async {
    final store = InMemoryKeyValueStore();
    final seed = await buildTestContainer(store: store);
    await seed<SettingsRepository>().save(
      (await seed<SettingsRepository>().load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
      ),
    );

    final container = await buildTestContainer(store: store);
    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(HomeKeys.scanAndSend));
    await tester.pumpAndSettle();

    expect(find.byKey(ScanKeys.capture), findsOneWidget);
  });
}
