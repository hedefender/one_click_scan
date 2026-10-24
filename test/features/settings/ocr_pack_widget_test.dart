import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/core/config/app_config.dart';
import 'package:one_click_scan/domain/entities/app_language.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/settings/settings_keys.dart';

import '../../support/fakes.dart';

void main() {
  late SettingsRepository repository;

  Future<void> pumpSettings(
    WidgetTester tester, {
    String deviceLanguage = 'en',
    String? storedPack,
  }) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = InMemoryKeyValueStore();
    final config = AppConfig.forDeviceLanguage(deviceLanguage);
    final seed = await buildTestContainer(store: store, config: config);
    await seed<SettingsRepository>().save(
      (await seed<SettingsRepository>().load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        mailProvider: MailProviderId.gmail,
        senderAccount: 'sender@example.com',
        ocrPackId: storedPack,
      ),
    );
    final container = await buildTestContainer(store: store, config: config);
    repository = container<SettingsRepository>();
    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeKeys.settings));
    await tester.pumpAndSettle();
  }

  RadioListTile<String> tile(WidgetTester tester, String id) => tester
      .widget<RadioListTile<String>>(find.byKey(SettingsKeys.ocrPack(id)));

  testWidgets('both bundled packs are listed with name and description', (
    tester,
  ) async {
    await pumpSettings(tester);

    expect(find.text('Text reading language (OCR)'), findsOneWidget);
    expect(find.text('Greek + English'), findsOneWidget);
    expect(find.text('Latin script'), findsOneWidget);
    expect(find.textContaining('Does not read Greek'), findsOneWidget);
    expect(find.byKey(SettingsKeys.ocrPack('greek')), findsOneWidget);
    expect(find.byKey(SettingsKeys.ocrPack('latin')), findsOneWidget);
  });

  testWidgets('the note says the app does not guess the language', (
    tester,
  ) async {
    await pumpSettings(tester);

    expect(find.textContaining('does not guess the language'), findsOneWidget);
  });

  testWidgets('English device: latin is selected on the first visit', (
    tester,
  ) async {
    await pumpSettings(tester, deviceLanguage: 'en', storedPack: null);

    final group = tester.widget<RadioGroup<String>>(
      find.byType(RadioGroup<String>),
    );
    expect(group.groupValue, 'latin');
    expect(tile(tester, 'latin').value, 'latin');
  });

  testWidgets('Greek device: greek is selected on the first visit', (
    tester,
  ) async {
    await pumpSettings(tester, deviceLanguage: 'el', storedPack: null);

    final group = tester.widget<RadioGroup<String>>(
      find.byType(RadioGroup<String>),
    );
    expect(group.groupValue, 'greek');
  });

  testWidgets('choosing a pack saves it at once', (tester) async {
    await pumpSettings(tester, deviceLanguage: 'en', storedPack: 'latin');

    await tester.ensureVisible(find.byKey(SettingsKeys.ocrPack('greek')));
    await tester.tap(find.byKey(SettingsKeys.ocrPack('greek')));
    await tester.pumpAndSettle();

    expect((await repository.load()).ocrPackId, 'greek');
    final group = tester.widget<RadioGroup<String>>(
      find.byType(RadioGroup<String>),
    );
    expect(group.groupValue, 'greek');
  });

  testWidgets('the Greek UI describes the packs in Greek', (tester) async {
    await pumpSettings(tester, deviceLanguage: 'el');
    await repository.save(
      (await repository.load()).copyWith(language: AppLanguage.el),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ελληνικά + Αγγλικά'), findsOneWidget);
    expect(find.text('Λατινική γραφή'), findsOneWidget);
  });

  testWidgets('the licence screen can be opened from the settings', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.ensureVisible(find.byKey(SettingsKeys.licenses));
    expect(find.text('Open-source licences'), findsOneWidget);
    await tester.tap(find.byKey(SettingsKeys.licenses));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
  });
}
