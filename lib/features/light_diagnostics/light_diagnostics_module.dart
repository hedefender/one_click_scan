import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/route_paths.dart';
import '../../domain/ports/light_meter.dart';
import '../../services/camera/camera_service.dart';
import '../../services/scan_files/scan_temp_store.dart';
import 'light_diagnostics_cubit.dart';
import 'light_diagnostics_page.dart';

List<RouteBase> lightDiagnosticsRoutes(GetIt sl) {
  return [
    GoRoute(
      path: RoutePaths.lightDiagnostics,
      builder: (context, state) => RepositoryProvider<CameraService>.value(
        value: sl<CameraService>(),
        child: BlocProvider<LightDiagnosticsCubit>(
          create: (_) => LightDiagnosticsCubit(
            camera: sl<CameraService>(),
            meter: sl<LightMeter>(),
            tempStore: sl<ScanTempStore>(),
          )..start(),
          child: const LightDiagnosticsPage(),
        ),
      ),
    ),
  ];
}
