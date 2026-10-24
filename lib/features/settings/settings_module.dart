import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../core/logging/app_logger.dart';
import '../../core/navigation/route_paths.dart';
import '../../domain/ocr/ocr_language_pack_registry.dart';
import '../../domain/usecases/load_settings.dart';
import '../../domain/usecases/update_settings.dart';
import '../../services/storage_folder/storage_folder_picker.dart';
import 'settings_editor_cubit.dart';
import 'settings_page.dart';

/// Feature module: owns its DI registrations and its routes.
void registerSettingsModule(GetIt sl) {
  sl.registerFactory<SettingsEditorCubit>(
    () => SettingsEditorCubit(
      loadSettings: sl<LoadSettings>(),
      updateSettings: sl<UpdateSettings>(),
      folderPicker: sl<StorageFolderPicker>(),
      logger: sl<AppLogger>(),
    ),
  );
}

List<RouteBase> settingsRoutes(GetIt sl) {
  return [
    GoRoute(
      path: RoutePaths.settings,
      builder: (context, state) =>
          RepositoryProvider<OcrLanguagePackRegistry>.value(
            value: sl<OcrLanguagePackRegistry>(),
            child: BlocProvider<SettingsEditorCubit>(
              create: (_) => sl<SettingsEditorCubit>()..start(),
              child: const SettingsPage(),
            ),
          ),
    ),
  ];
}
