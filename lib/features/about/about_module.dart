import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/feedback_config.dart';
import '../../core/navigation/route_paths.dart';
import 'about_page.dart';

/// Feature module: About and the feedback button. The ports it reads
/// (`AppInfoSource`, `LinkOpener`, `FeedbackComposer`) live in the container.
List<RouteBase> aboutRoutes(
  GetIt sl, {
  String feedbackRecipient = FeedbackConfig.recipient,
}) {
  return [
    GoRoute(
      path: RoutePaths.about,
      builder: (context, state) =>
          AboutPage.fromContainer(sl, feedbackRecipient: feedbackRecipient),
    ),
  ];
}
