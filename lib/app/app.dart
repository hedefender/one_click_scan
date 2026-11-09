import 'package:dynamic_color/dynamic_color.dart';
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
  const OneClickScanApp({
    super.key,
    required this.container,
    this.useSystemColors = true,
  });

  final GetIt container;

  /// False keeps the fallback palettes even where the system gives colours
  /// (the screenshot tool uses it to show both looks).
  final bool useSystemColors;

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
          // System colours (Android 12+) when there are any, else the fallback
          // palettes; light or dark follows the device (no setting).
          return DynamicColorBuilder(
            builder: (lightDynamic, darkDynamic) {
              final systemLight = widget.useSystemColors
                  ? lightDynamic?.harmonized()
                  : null;
              final systemDark = widget.useSystemColors
                  ? darkDynamic?.harmonized()
                  : null;
              return MaterialApp.router(
                title: 'One Click Scan',
                routerConfig: _router,
                themeMode: ThemeMode.system,
                theme: AppTheme.light(
                  systemLight: systemLight,
                  systemDark: systemDark,
                ),
                darkTheme: AppTheme.dark(
                  systemLight: systemLight,
                  systemDark: systemDark,
                ),
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
          );
        },
      ),
    );
  }
}
