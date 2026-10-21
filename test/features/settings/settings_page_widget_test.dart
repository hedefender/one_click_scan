import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/domain/entities/app_language.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/storage_folder.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/settings/settings_keys.dart';

import '../../support/fakes.dart';

void main() {
  late FakeStorageFolderPicker picker;
  late SettingsRepository repository;

  /// Starts the app on home with a finished wizard stored.
  Future<void> pumpHome(WidgetTester tester) async {
    // Tall viewport so the whole settings list is on screen.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    picker = FakeStorageFolderPicker();
    final store = InMemoryKeyValueStore();
    final seed = await buildTestContainer(store: store, picker: picker);
    await seed<SettingsRepository>().save(
      (await seed<SettingsRepository>().load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        mailProvider: MailProviderId.gmail,
        senderAccount: 'sender@example.com',
      ),
    );
    final container = await buildTestContainer(store: store, picker: picker);
    repository = container<SettingsRepository>();
    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byKey(HomeKeys.settings));
    await tester.pumpAndSettle();
  }

  Future<void> tapBack(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
  }

  Future<void> enterSender(WidgetTester tester, String value) async {
    await tester.enterText(find.byKey(SettingsKeys.sender), value);
    await tester.pumpAndSettle();
  }

  FilledButton saveButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(SettingsKeys.save));

  testWidgets('settings open from the home app bar', (tester) async {
    await pumpHome(tester);
    await openSettings(tester);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Selected folder: Scans'), findsOneWidget);
    expect(find.byKey(SettingsKeys.save), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);
  });

  testWidgets('invalid email shows the wizard error and disables Save', (
    tester,
  ) async {
    await pumpHome(tester);
    await openSettings(tester);

    await enterSender(tester, 'nope');
    expect(find.text('Invalid email address.'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);

    await enterSender(tester, 'new@example.com');
    expect(find.text('Invalid email address.'), findsNothing);
    expect(saveButton(tester).onPressed, isNotNull);
  });

  testWidgets('saving persists the email and home shows it', (tester) async {
    await pumpHome(tester);
    await openSettings(tester);

    await enterSender(tester, 'new@example.com');
    await tester.tap(find.byKey(SettingsKeys.save));
    await tester.pumpAndSettle();

    expect(find.text('Settings saved.'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);
    expect((await repository.load()).senderAccount, 'new@example.com');

    await tapBack(tester); // no dialog: nothing unsaved
    expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);
    expect(find.text('new@example.com'), findsOneWidget);
  });

  testWidgets('leaving without changes does not ask', (tester) async {
    await pumpHome(tester);
    await openSettings(tester);
    await tapBack(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);
  });

  testWidgets('leaving with unsaved changes asks; Stay keeps editing', (
    tester,
  ) async {
    await pumpHome(tester);
    await openSettings(tester);
    await enterSender(tester, 'new@example.com');

    await tapBack(tester);
    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.tap(find.byKey(SettingsKeys.dialogStay));
    await tester.pumpAndSettle();
    expect(find.byKey(SettingsKeys.save), findsOneWidget);
    expect(find.text('new@example.com'), findsOneWidget);
  });

  testWidgets('Discard leaves and drops the unsaved changes', (tester) async {
    await pumpHome(tester);
    await openSettings(tester);
    await enterSender(tester, 'new@example.com');

    await tapBack(tester);
    await tester.tap(find.byKey(SettingsKeys.dialogDiscard));
    await tester.pumpAndSettle();

    expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);
    expect(find.text('sender@example.com'), findsOneWidget);
    expect((await repository.load()).senderAccount, 'sender@example.com');
  });

  testWidgets('language change applies and persists at once', (tester) async {
    await pumpHome(tester);
    await openSettings(tester);

    await tester.tap(find.text('Ελληνικά'));
    await tester.pumpAndSettle();

    expect(find.text('Ρυθμίσεις'), findsOneWidget);
    expect(find.text('Αποθήκευση'), findsOneWidget);
    expect((await repository.load()).language, AppLanguage.el);
  });

  testWidgets('Gallery switch is saved immediately', (tester) async {
    await pumpHome(tester);
    await openSettings(tester);

    await tester.tap(find.byKey(SettingsKeys.gallerySwitch));
    await tester.pumpAndSettle();

    expect((await repository.load()).saveToGallery, isTrue);
  });

  testWidgets('changing the folder updates settings and home', (tester) async {
    await pumpHome(tester);
    await openSettings(tester);

    picker.result = const StorageFolder(
      uri: 'content://com.example.test/tree/primary%3AOther',
      name: 'Other',
    );
    await tester.tap(find.byKey(SettingsKeys.changeFolder));
    await tester.pumpAndSettle();
    expect(find.text('Selected folder: Other'), findsOneWidget);

    await tapBack(tester);
    expect(find.text('Other'), findsOneWidget);
  });

  testWidgets('settings warn when folder access is lost', (tester) async {
    await pumpHome(tester);
    picker.accessGranted = false;
    await openSettings(tester);

    expect(find.byKey(SettingsKeys.folderAccessWarning), findsOneWidget);

    picker.accessGranted = true;
    await tester.tap(find.byKey(SettingsKeys.changeFolder));
    await tester.pumpAndSettle();
    expect(find.byKey(SettingsKeys.folderAccessWarning), findsNothing);
  });

  testWidgets('home shows no banner while the folder is accessible', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(find.byKey(HomeKeys.folderLostBanner), findsNothing);
  });

  testWidgets('home banner appears when access is lost and leads to settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    picker = FakeStorageFolderPicker()..accessGranted = false;
    final store = InMemoryKeyValueStore();
    final seed = await buildTestContainer(store: store, picker: picker);
    await seed<SettingsRepository>().save(
      (await seed<SettingsRepository>().load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
      ),
    );
    final container = await buildTestContainer(store: store, picker: picker);
    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();

    expect(find.text('The folder is no longer accessible'), findsOneWidget);

    await tester.tap(find.byKey(HomeKeys.folderLostAction));
    await tester.pumpAndSettle();
    expect(find.byKey(SettingsKeys.changeFolder), findsOneWidget);

    // Picking a folder again and returning clears the banner.
    picker.accessGranted = true;
    await tester.tap(find.byKey(SettingsKeys.changeFolder));
    await tester.pumpAndSettle();
    await tapBack(tester);
    expect(find.byKey(HomeKeys.folderLostBanner), findsNothing);
  });
}
