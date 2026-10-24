import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/route_paths.dart';
import '../../domain/usecases/recognize_pages.dart';
import 'ocr_result_cubit.dart';
import 'ocr_result_page.dart';

/// Feature module: the OCR check screen. It has no registrations of its own
/// (the cubit wraps the session that the scan hands over).
List<RouteBase> ocrRoutes(GetIt sl) {
  return [
    GoRoute(
      path: RoutePaths.ocrResult,
      // The session is passed as `extra`; without it (for example after a
      // process restart) there is nothing to show.
      redirect: (context, state) =>
          state.extra is OcrSession ? null : RoutePaths.home,
      builder: (context, state) => BlocProvider<OcrResultCubit>(
        create: (_) => OcrResultCubit(state.extra! as OcrSession),
        child: const OcrResultPage(),
      ),
    ),
  ];
}
