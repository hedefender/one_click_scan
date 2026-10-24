import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/data/datasources/settings_local_data_source.dart';
import 'package:one_click_scan/data/repositories/settings_repository_impl.dart';
import 'package:one_click_scan/domain/entities/app_language.dart';
import 'package:one_click_scan/domain/entities/app_settings.dart';
import 'package:one_click_scan/domain/entities/destination_mode.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/usecases/load_settings.dart';
import 'package:one_click_scan/domain/usecases/update_settings.dart';

import '../support/fakes.dart';

void main() {
  late InMemoryKeyValueStore store;
  late SettingsRepositoryImpl repository;

  SettingsRepositoryImpl makeRepository(AppLanguage defaultLanguage) {
    return SettingsRepositoryImpl(
      SettingsLocalDataSource(
        store: store,
        schemaVersion: 1,
        defaultLanguage: defaultLanguage,
      ),
    );
  }

  setUp(() {
    store = InMemoryKeyValueStore();
    repository = makeRepository(AppLanguage.en);
  });

  test('empty store yields defaults with the configured language', () async {
    expect(
      await repository.load(),
      const AppSettings(language: AppLanguage.en),
    );
    expect(
      await makeRepository(AppLanguage.el).load(),
      // A Greek device starts with the Greek OCR pack, every other with Latin.
      const AppSettings(language: AppLanguage.el, ocrPackId: 'greek'),
    );
  });

  test('save then load round-trips every field', () async {
    final settings = const AppSettings(language: AppLanguage.el).copyWith(
      firstRunCompleted: true,
      storageFolder: testFolder,
      mailProvider: MailProviderId.outlook,
      senderAccount: 'sender@example.com',
      destinationMode: DestinationMode.custom,
      customDestination: 'other@example.com',
      saveToGallery: true,
      ocrPackId: 'greek',
    );

    await repository.save(settings);

    expect(await makeRepository(AppLanguage.en).load(), settings);
    expect(store.getInt(SettingsLocalDataSource.keySchemaVersion), 1);
  });

  test('saving null removes optional keys', () async {
    await repository.save(
      const AppSettings(language: AppLanguage.en).copyWith(
        storageFolder: testFolder,
        senderAccount: 'sender@example.com',
      ),
    );
    await repository.save(const AppSettings(language: AppLanguage.en));

    expect(store.getString(SettingsLocalDataSource.keyStorageUri), isNull);
    expect(store.getString(SettingsLocalDataSource.keyMailSender), isNull);
    expect((await repository.load()).storageFolder, isNull);
  });

  test('unknown or corrupted values fall back to defaults', () async {
    await store.setString(SettingsLocalDataSource.keyLanguage, 'zz');
    await store.setString(SettingsLocalDataSource.keyMailProvider, 'bogus');
    await store.setString(SettingsLocalDataSource.keyDestinationMode, 'nope');

    final loaded = await repository.load();

    expect(loaded.language, AppLanguage.en);
    expect(loaded.mailProvider, isNull);
    expect(loaded.destinationMode, DestinationMode.own);
  });

  test('folder name falls back to the URI when the name is missing', () async {
    await store.setString(
      SettingsLocalDataSource.keyStorageUri,
      'content://example/tree/1',
    );

    final loaded = await repository.load();

    expect(loaded.storageFolder?.uri, 'content://example/tree/1');
    expect(loaded.storageFolder?.name, 'content://example/tree/1');
  });

  test('changes stream emits after save', () async {
    final emitted = expectLater(
      repository.changes,
      emits(const AppSettings(language: AppLanguage.el)),
    );

    await repository.save(const AppSettings(language: AppLanguage.el));
    await emitted;
  });

  group('use cases', () {
    test('UpdateSettings applies the transform and persists it', () async {
      final update = UpdateSettings(repository);
      final load = LoadSettings(repository);

      final updated = await update(
        (current) => current.copyWith(saveToGallery: true),
      );

      expect(updated.saveToGallery, isTrue);
      expect((await load()).saveToGallery, isTrue);
    });

    test(
      'UpdateSettings preserves fields the transform does not touch',
      () async {
        final update = UpdateSettings(repository);
        await update(
          (current) => current.copyWith(senderAccount: 'a@example.com'),
        );
        await update((current) => current.copyWith(saveToGallery: true));

        final loaded = await LoadSettings(repository)();
        expect(loaded.senderAccount, 'a@example.com');
        expect(loaded.saveToGallery, isTrue);
      },
    );
  });
}
