import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../core/navigation/route_paths.dart';
import '../domain/entities/app_settings.dart';
import '../presentation/l10n/app_strings.dart';
import '../presentation/state/settings_cubit.dart';
import '../presentation/theme/app_theme.dart';
import 'router.dart';

class OneClickScanApp extends StatefulWidget {
  const OneClickScanApp({super.key, required this.container});

  final GetIt container;

  @override
  State<OneClickScanApp> createState() => _OneClickScanAppState();
}

class _OneClickScanAppState extends State<OneClickScanApp> {
  late final SettingsCubit _settingsCubit;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _settingsCubit = widget.container<SettingsCubit>();
    _router = createRouter(
      container: widget.container,
      initialLocation: RoutePaths.initialFor(
        firstRunCompleted: _settingsCubit.state.firstRunCompleted,
      ),
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SettingsCubit>.value(
      value: _settingsCubit,
      child: BlocBuilder<SettingsCubit, AppSettings>(
        buildWhen: (previous, current) => previous.language != current.language,
        builder: (context, settings) {
          return MaterialApp.router(
            title: 'One Click Scan',
            routerConfig: _router,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            locale: Locale(settings.language.code),
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              AppStrings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          );
        },
      ),
    );
  }
}
