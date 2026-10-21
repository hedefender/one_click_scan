import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../core/logging/app_logger.dart';
import '../../core/navigation/route_paths.dart';
import '../../domain/entities/stored_scan.dart';
import '../../domain/usecases/load_settings.dart';
import '../../domain/usecases/store_scan_pages.dart';
import '../../services/camera/camera_service.dart';
import '../../services/scan_files/scan_temp_store.dart';
import '../../services/storage_folder/storage_folder_picker.dart';
import 'scan_cubit.dart';
import 'scan_page.dart';
import 'scan_result_page.dart';

/// Feature module: owns its DI registrations and its routes.
void registerScanModule(GetIt sl) {
  sl.registerFactory<ScanCubit>(
    () => ScanCubit(
      loadSettings: sl<LoadSettings>(),
      folderPicker: sl<StorageFolderPicker>(),
      camera: sl<CameraService>(),
      storeScanPages: sl<StoreScanPages>(),
      tempStore: sl<ScanTempStore>(),
      logger: sl<AppLogger>(),
    ),
  );
}

List<RouteBase> scanRoutes(GetIt sl) {
  return [
    GoRoute(
      path: RoutePaths.scan,
      builder: (context, state) => RepositoryProvider<CameraService>.value(
        value: sl<CameraService>(),
        child: BlocProvider<ScanCubit>(
          create: (_) => sl<ScanCubit>()..start(),
          child: const ScanPage(),
        ),
      ),
    ),
    GoRoute(
      path: RoutePaths.scanResult,
      // The result is passed as `extra`; without it (for example after a
      // process restart) there is nothing to show.
      redirect: (context, state) =>
          state.extra is StoredScan ? null : RoutePaths.home,
      builder: (context, state) => RepositoryProvider<ScanTempStore>.value(
        value: sl<ScanTempStore>(),
        child: ScanResultPage(result: state.extra! as StoredScan),
      ),
    ),
  ];
}
