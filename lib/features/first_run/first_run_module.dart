import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../core/logging/app_logger.dart';
import '../../core/navigation/route_paths.dart';
import '../../domain/usecases/load_settings.dart';
import '../../domain/usecases/update_settings.dart';
import '../../services/storage_folder/storage_folder_picker.dart';
import 'first_run_cubit.dart';
import 'first_run_page.dart';

/// Feature module: owns its DI registrations and its routes.
void registerFirstRunModule(GetIt sl) {
  sl.registerFactory<FirstRunCubit>(
    () => FirstRunCubit(
      loadSettings: sl<LoadSettings>(),
      updateSettings: sl<UpdateSettings>(),
      folderPicker: sl<StorageFolderPicker>(),
      logger: sl<AppLogger>(),
    ),
  );
}

List<RouteBase> firstRunRoutes(GetIt sl) {
  return [
    GoRoute(
      path: RoutePaths.firstRun,
      builder: (context, state) => BlocProvider<FirstRunCubit>(
        create: (_) => sl<FirstRunCubit>()..start(),
        child: const FirstRunPage(),
      ),
    ),
  ];
}
