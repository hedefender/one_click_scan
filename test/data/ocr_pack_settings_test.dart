import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/core/config/app_config.dart';
import 'package:one_click_scan/data/datasources/settings_local_data_source.dart';
import 'package:one_click_scan/data/repositories/settings_repository_impl.dart';
import 'package:one_click_scan/domain/entities/app_language.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/domain/usecases/update_settings.dart';
import 'package:one_click_scan/features/settings/settings_editor_cubit.dart';

import '../support/fakes.dart';

void main() {
  late InMemoryKeyValueStore store;

  SettingsRepositoryImpl repositoryFor(AppLanguage deviceLanguage) {
    return SettingsRepositoryImpl(
      SettingsLocalDataSource(
        store: store,
        schemaVersion: 1,
        defaultLanguage: deviceLanguage,
      ),
    );
  }

  setUp(() => store = InMemoryKeyValueStore());

  group('first run default', () {
    test('Greek device: the greek pack', () async {
      final settings = await repositoryFor(AppLanguage.el).load();

      expect(settings.ocrPackId, 'greek');
    });

    test('English device: the latin pack', () async {
      final settings = await repositoryFor(AppLanguage.en).load();

      expect(settings.ocrPackId, 'latin');
    });

    test(
      'the default follows the device language, not the app language',
      () async {
        // Device in English, then the user switches the app to Greek.
        final repo = repositoryFor(AppLanguage.en);
        await repo.save((await repo.load()).copyWith(language: AppLanguage.el));

        expect((await repo.load()).ocrPackId, 'latin');
      },
    );
  });

  group('the choice is stored', () {
    test('it survives a restart and wins over the device language', () async {
      final repo = repositoryFor(AppLanguage.el);
      await repo.save((await repo.load()).copyWith(ocrPackId: 'latin'));

      expect((await repositoryFor(AppLanguage.el).load()).ocrPackId, 'latin');
      expect(store.getString(SettingsLocalDataSource.keyOcrPack), 'latin');
    });

    test('an unknown stored id falls back to the default', () async {
      await store.setString(SettingsLocalDataSource.keyOcrPack, 'klingon');

      expect((await repositoryFor(AppLanguage.el).load()).ocrPackId, 'greek');
      expect((await repositoryFor(AppLanguage.en).load()).ocrPackId, 'latin');
    });

    test('an empty stored value falls back to the default', () async {
      await store.setString(SettingsLocalDataSource.keyOcrPack, '');

      expect((await repositoryFor(AppLanguage.en).load()).ocrPackId, 'latin');
    });
  });

  group('SettingsEditorCubit.selectOcrPack', () {
    test('saves at once and the repository sees it', () async {
      final container = await buildTestContainer(
        store: store,
        config: AppConfig.forDeviceLanguage('el'),
      );
      final cubit = container<SettingsEditorCubit>();
      await cubit.start();
      expect(cubit.state.saved!.ocrPackId, 'greek');

      await cubit.selectOcrPack('latin');

      expect(cubit.state.saved!.ocrPackId, 'latin');
      expect((await container<SettingsRepository>().load()).ocrPackId, 'latin');
      await cubit.close();
    });

    test('UpdateSettings keeps the pack when other settings change', () async {
      final repo = repositoryFor(AppLanguage.el);
      await repo.save((await repo.load()).copyWith(ocrPackId: 'latin'));

      final updated = await UpdateSettings(repo)(
        (s) => s.copyWith(saveToGallery: true),
      );

      expect(updated.ocrPackId, 'latin');
    });
  });
}
