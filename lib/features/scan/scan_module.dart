import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../core/logging/app_logger.dart';
import '../../core/navigation/route_paths.dart';
import '../../domain/usecases/load_settings.dart';
import '../../domain/usecases/recognize_pages.dart';
import '../../domain/ports/open_pdf.dart';
import '../../domain/usecases/store_scan_pages.dart';
import '../../domain/usecases/store_scan_pdf.dart';
import '../../services/camera/camera_service.dart';
import '../../services/scan_files/scan_temp_store.dart';
import '../../services/storage_folder/storage_folder_picker.dart';
import '../../domain/usecases/send_scan_pdf.dart';
import 'mail_send_cubit.dart';
import 'scan_cubit.dart';
import 'scan_page.dart';
import 'scan_result_args.dart';
import 'scan_result_cubit.dart';
import 'scan_result_page.dart';

/// Feature module: owns its DI registrations and its routes.
void registerScanModule(GetIt sl) {
  sl.registerFactory<ScanCubit>(
    () => ScanCubit(
      loadSettings: sl<LoadSettings>(),
      folderPicker: sl<StorageFolderPicker>(),
      camera: sl<CameraService>(),
      storeScanPages: sl<StoreScanPages>(),
      recognizePages: sl<RecognizePages>(),
      tempStore: sl<ScanTempStore>(),
      logger: sl<AppLogger>(),
    ),
  );
  sl.registerFactoryParam<ScanResultCubit, ScanResultArgs, void>(
    (args, _) => ScanResultCubit(
      scan: args.result,
      session: args.ocr,
      loadSettings: sl<LoadSettings>(),
      storePdf: sl<StoreScanPdf>(),
      openPdf: sl<OpenPdf>(),
      logger: sl<AppLogger>(),
    ),
  );
  sl.registerFactory<MailSendCubit>(
    () => MailSendCubit(
      loadSettings: sl<LoadSettings>(),
      send: sl<SendScanPdf>(),
      share: sl<ShareScanPdfDraft>(),
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
          state.extra is ScanResultArgs ? null : RoutePaths.home,
      builder: (context, state) {
        final args = state.extra! as ScanResultArgs;
        return RepositoryProvider<ScanTempStore>.value(
          value: sl<ScanTempStore>(),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ScanResultCubit>(
                create: (_) => sl<ScanResultCubit>(param1: args)..start(),
              ),
              BlocProvider<MailSendCubit>(create: (_) => sl<MailSendCubit>()),
            ],
            child: ScanResultPage(args: args),
          ),
        );
      },
    ),
  ];
}
