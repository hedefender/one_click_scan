import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/app_language.dart';
import 'package:one_click_scan/domain/entities/app_settings.dart';
import 'package:one_click_scan/domain/entities/destination_mode.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/storage_folder.dart';

void main() {
  const base = AppSettings(language: AppLanguage.en);

  test('defaults are privacy friendly and incomplete', () {
    expect(base.firstRunCompleted, isFalse);
    expect(base.saveToGallery, isFalse);
    expect(base.destinationMode, DestinationMode.own);
    expect(base.storageFolder, isNull);
    expect(base.mailProvider, isNull);
    expect(base.effectiveDestination, isNull);
  });

  test('effectiveDestination follows the destination mode', () {
    final own = base.copyWith(
      senderAccount: 'sender@example.com',
      customDestination: 'other@example.com',
    );
    expect(own.effectiveDestination, 'sender@example.com');

    final custom = own.copyWith(destinationMode: DestinationMode.custom);
    expect(custom.effectiveDestination, 'other@example.com');
  });

  test('copyWith keeps untouched fields and can clear nullable ones', () {
    final full = base.copyWith(
      storageFolder: const StorageFolder(uri: 'content://x', name: 'x'),
      mailProvider: MailProviderId.gmail,
    );
    expect(full.copyWith(saveToGallery: true).storageFolder, isNotNull);
    expect(
      full.copyWith(saveToGallery: true).mailProvider,
      MailProviderId.gmail,
    );

    expect(full.copyWith(storageFolder: null).storageFolder, isNull);
    expect(full.copyWith(mailProvider: null).mailProvider, isNull);
  });

  test('value equality', () {
    expect(base.copyWith(), base);
    expect(base.copyWith(firstRunCompleted: true), isNot(base));
  });

  test('AppLanguage.fromCode', () {
    expect(AppLanguage.fromCode('el'), AppLanguage.el);
    expect(AppLanguage.fromCode('en'), AppLanguage.en);
    expect(AppLanguage.fromCode('xx'), isNull);
    expect(AppLanguage.fromCode(null), isNull);
  });
}
