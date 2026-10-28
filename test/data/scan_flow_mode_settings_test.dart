import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/data/datasources/settings_local_data_source.dart';
import 'package:one_click_scan/domain/entities/app_language.dart';
import 'package:one_click_scan/domain/entities/app_settings.dart';
import 'package:one_click_scan/domain/entities/scan_flow_mode.dart';

import '../support/fakes.dart';

void main() {
  late InMemoryKeyValueStore store;
  late SettingsLocalDataSource source;

  setUp(() {
    store = InMemoryKeyValueStore();
    source = SettingsLocalDataSource(
      store: store,
      schemaVersion: 1,
      defaultLanguage: AppLanguage.en,
    );
  });

  group('no choice yet (an install from before Phase 5, or the wizard)', () {
    test('the value is absent, not a default', () {
      expect(const AppSettings(language: AppLanguage.en).scanFlowMode, isNull);
      expect(source.read().scanFlowMode, isNull);
    });

    test('and the app then behaves as the preview', () {
      expect(
        source.read().effectiveScanFlowMode,
        ScanFlowMode.preview,
        reason: 'ADR-025: an existing install keeps seeing the pages first',
      );
    });

    test(
      'an old store with every other key set still reads as unknown',
      () async {
        await store.setBool('settings.firstRunCompleted', true);
        await store.setString('settings.mail.sendMode', 'sendNow');
        await store.setString('settings.mail.provider', 'gmail');

        final read = source.read();

        expect(read.firstRunCompleted, isTrue);
        expect(read.scanFlowMode, isNull);
        expect(read.effectiveScanFlowMode, ScanFlowMode.preview);
      },
    );

    test(
      'writing settings that never chose does not invent a choice',
      () async {
        await source.write(const AppSettings(language: AppLanguage.en));

        expect(store.getString('settings.scan.flowMode'), isNull);
        expect(source.read().scanFlowMode, isNull);
      },
    );
  });

  test('both choices are stored and read back, by name', () async {
    for (final mode in ScanFlowMode.values) {
      await source.write(
        AppSettings(language: AppLanguage.en, scanFlowMode: mode),
      );

      expect(store.getString('settings.scan.flowMode'), mode.name);
      expect(source.read().scanFlowMode, mode);
      expect(source.read().effectiveScanFlowMode, mode);
    }
  });

  test('an unknown stored value is read as no choice', () async {
    await store.setString('settings.scan.flowMode', 'telepathy');

    expect(source.read().scanFlowMode, isNull);
    expect(source.read().effectiveScanFlowMode, ScanFlowMode.preview);
  });

  test('copyWith sets it, keeps it, and null clears it', () {
    const before = AppSettings(language: AppLanguage.el, saveToGallery: true);

    final chosen = before.copyWith(scanFlowMode: ScanFlowMode.oneClick);
    expect(chosen.scanFlowMode, ScanFlowMode.oneClick);
    expect(chosen.saveToGallery, isTrue);

    expect(
      chosen.copyWith(saveToGallery: false).scanFlowMode,
      ScanFlowMode.oneClick,
    );
    expect(chosen.copyWith(scanFlowMode: null).scanFlowMode, isNull);
    expect(before.scanFlowMode, isNull);
  });

  test('the choice takes part in equality', () {
    const a = AppSettings(language: AppLanguage.en);
    expect(a, isNot(a.copyWith(scanFlowMode: ScanFlowMode.oneClick)));
    expect(
      a.copyWith(scanFlowMode: ScanFlowMode.preview),
      a.copyWith(scanFlowMode: ScanFlowMode.preview),
    );
  });
}
