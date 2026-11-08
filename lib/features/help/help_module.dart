import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/route_paths.dart';
import 'guide_page.dart';
import 'help_page.dart';

/// Feature module: the Help screen and the guide page. Both only show text
/// (`AppStrings.guideSections`), so nothing is registered in the container.
List<RouteBase> helpRoutes(GetIt sl) {
  return [
    GoRoute(
      path: RoutePaths.help,
      builder: (context, state) => const HelpPage(),
    ),
    GoRoute(
      path: RoutePaths.helpGuide,
      builder: (context, state) => const GuidePage(),
    ),
  ];
}
