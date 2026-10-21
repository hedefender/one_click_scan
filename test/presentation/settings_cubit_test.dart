import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/data/datasources/settings_local_data_source.dart';
import 'package:one_click_scan/data/repositories/settings_repository_impl.dart';
import 'package:one_click_scan/domain/entities/app_language.dart';
import 'package:one_click_scan/domain/entities/app_settings.dart';
import 'package:one_click_scan/presentation/state/settings_cubit.dart';

import '../support/fakes.dart';

void main() {
  test('mirrors every saved change and stops after close', () async {
    final repository = SettingsRepositoryImpl(
      SettingsLocalDataSource(
        store: InMemoryKeyValueStore(),
        schemaVersion: 1,
        defaultLanguage: AppLanguage.en,
      ),
    );
    const initial = AppSettings(language: AppLanguage.en);
    final cubit = SettingsCubit(repository, initial);

    expect(cubit.state, initial);

    const changed = AppSettings(
      language: AppLanguage.el,
      firstRunCompleted: true,
    );
    await repository.save(changed);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state, changed);

    await cubit.close();
    // Saving after close must not throw.
    await repository.save(initial);
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state, changed);
  });
}
