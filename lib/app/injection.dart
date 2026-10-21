import 'package:get_it/get_it.dart';

import '../core/config/app_config.dart';
import '../core/logging/app_logger.dart';
import '../data/datasources/key_value_store.dart';
import '../data/datasources/settings_local_data_source.dart';
import '../data/repositories/settings_repository_impl.dart';
import '../domain/entities/app_language.dart';
import '../domain/repositories/settings_repository.dart';
import '../domain/usecases/load_settings.dart';
import '../domain/usecases/update_settings.dart';
import '../features/first_run/first_run_module.dart';
import '../features/home/home_module.dart';
import '../features/settings/settings_module.dart';
import '../presentation/state/settings_cubit.dart';
import '../services/storage_folder/storage_folder_picker.dart';

/// Composition root.
///
/// Builds a fresh container each call (no global singleton), which keeps
/// tests isolated: platform adapters are passed in, so tests inject fakes.
Future<GetIt> buildContainer({
  required AppConfig config,
  required KeyValueStore keyValueStore,
  required StorageFolderPicker folderPicker,
  AppLogger logger = const DebugAppLogger(),
}) async {
  final sl = GetIt.asNewInstance();

  // Core and platform adapters.
  sl.registerSingleton<AppConfig>(config);
  sl.registerSingleton<AppLogger>(logger);
  sl.registerSingleton<KeyValueStore>(keyValueStore);
  sl.registerSingleton<StorageFolderPicker>(folderPicker);

  // Data.
  sl.registerLazySingleton<SettingsLocalDataSource>(
    () => SettingsLocalDataSource(
      store: sl<KeyValueStore>(),
      schemaVersion: sl<AppConfig>().settingsSchemaVersion,
      defaultLanguage:
          AppLanguage.fromCode(sl<AppConfig>().defaultLanguageCode) ??
          AppLanguage.en,
    ),
  );
  sl.registerLazySingleton<SettingsRepository>(
    () => SettingsRepositoryImpl(sl<SettingsLocalDataSource>()),
  );

  // Domain.
  sl.registerLazySingleton<LoadSettings>(
    () => LoadSettings(sl<SettingsRepository>()),
  );
  sl.registerLazySingleton<UpdateSettings>(
    () => UpdateSettings(sl<SettingsRepository>()),
  );

  // Feature modules.
  registerFirstRunModule(sl);
  registerHomeModule(sl);
  registerSettingsModule(sl);

  // App-wide state, created after settings can be read.
  final initialSettings = await sl<LoadSettings>()();
  sl.registerSingleton<SettingsCubit>(
    SettingsCubit(sl<SettingsRepository>(), initialSettings),
  );

  return sl;
}
