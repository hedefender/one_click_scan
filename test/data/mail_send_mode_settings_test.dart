import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/data/datasources/settings_local_data_source.dart';
import 'package:one_click_scan/domain/entities/app_language.dart';
import 'package:one_click_scan/domain/entities/app_settings.dart';
import 'package:one_click_scan/domain/entities/mail_send_mode.dart';

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

  test('the default is to send from the app', () {
    expect(
      const AppSettings(language: AppLanguage.en).mailSendMode,
      MailSendMode.sendNow,
    );
    expect(source.read().mailSendMode, MailSendMode.sendNow);
  });

  test('the choice is stored and read back, by name', () async {
    await source.write(
      const AppSettings(
        language: AppLanguage.en,
        mailSendMode: MailSendMode.shareDraft,
      ),
    );

    expect(store.getString('settings.mail.sendMode'), 'shareDraft');
    expect(source.read().mailSendMode, MailSendMode.shareDraft);
  });

  test('an unknown stored value falls back to sending from the app', () async {
    await store.setString('settings.mail.sendMode', 'carrierPigeon');
    expect(source.read().mailSendMode, MailSendMode.sendNow);
  });

  test('copyWith changes it and nothing else', () {
    const before = AppSettings(language: AppLanguage.el, saveToGallery: true);
    final after = before.copyWith(mailSendMode: MailSendMode.shareDraft);

    expect(after.mailSendMode, MailSendMode.shareDraft);
    expect(after.saveToGallery, isTrue);
    expect(after.language, AppLanguage.el);
    expect(before.mailSendMode, MailSendMode.sendNow);
  });

  test('settings never hold a password: no field and no key', () async {
    await source.write(const AppSettings(language: AppLanguage.en));
    expect(
      store.data.keys.where((k) => k.toLowerCase().contains('pass')),
      isEmpty,
    );
    expect(
      store.data.keys.where((k) => k.toLowerCase().contains('secret')),
      isEmpty,
    );
  });
}
