import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../features/first_run/first_run_module.dart';
import '../features/home/home_module.dart';
import '../features/ocr/ocr_module.dart';
import '../features/scan/scan_module.dart';
import '../features/settings/settings_module.dart';

/// Composes the routes exposed by every feature module.
GoRouter createRouter({
  required GetIt container,
  required String initialLocation,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      ...firstRunRoutes(container),
      ...homeRoutes(container),
      ...settingsRoutes(container),
      ...scanRoutes(container),
      ...ocrRoutes(container),
    ],
  );
}
