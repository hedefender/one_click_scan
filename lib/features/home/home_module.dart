import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/route_paths.dart';
import 'home_page.dart';

/// Feature module for the home screen. Nothing to register in Phase 0.
void registerHomeModule(GetIt sl) {}

List<RouteBase> homeRoutes(GetIt sl) {
  return [
    GoRoute(
      path: RoutePaths.home,
      builder: (context, state) => const HomePage(),
    ),
  ];
}
