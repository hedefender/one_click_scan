import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../core/logging/app_logger.dart';
import '../../core/navigation/route_paths.dart';
import '../../domain/usecases/load_settings.dart';
import '../../services/storage_folder/storage_folder_picker.dart';
import 'home_cubit.dart';
import 'home_page.dart';

/// Feature module for the home screen.
void registerHomeModule(GetIt sl) {
  sl.registerFactory<HomeCubit>(
    () => HomeCubit(
      loadSettings: sl<LoadSettings>(),
      folderPicker: sl<StorageFolderPicker>(),
      logger: sl<AppLogger>(),
    ),
  );
}

List<RouteBase> homeRoutes(GetIt sl) {
  return [
    GoRoute(
      path: RoutePaths.home,
      builder: (context, state) => BlocProvider<HomeCubit>(
        create: (_) => sl<HomeCubit>()..checkFolderAccess(),
        child: const HomePage(),
      ),
    ),
  ];
}
