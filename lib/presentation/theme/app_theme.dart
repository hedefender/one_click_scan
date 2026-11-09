import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimens.dart';

/// Tells which colours the theme was built from (shown in the diagnostics).
@immutable
class AppColorSource extends ThemeExtension<AppColorSource> {
  const AppColorSource({required this.system});

  /// True when the colours come from the system (Android 12+ dynamic colour).
  final bool system;

  @override
  AppColorSource copyWith({bool? system}) =>
      AppColorSource(system: system ?? this.system);

  @override
  AppColorSource lerp(ThemeExtension<AppColorSource>? other, double t) =>
      other is AppColorSource ? other : this;
}

/// The central theme (DESIGN_SPEC). Every screen reads colours, text styles
/// and shapes from here, so the look changes in one place.
///
/// `systemLight` and `systemDark` are the schemes of the system colours
/// (already harmonised). When they are null the fallback palettes are used.
abstract final class AppTheme {
  static const String fontFamily = 'NotoSans';

  static ThemeData light({ColorScheme? systemLight, ColorScheme? systemDark}) {
    return _build(
      brightness: Brightness.light,
      system: systemLight,
      cameraSource: systemDark,
    );
  }

  static ThemeData dark({ColorScheme? systemLight, ColorScheme? systemDark}) {
    return _build(
      brightness: Brightness.dark,
      system: systemDark,
      cameraSource: systemDark,
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme? system,
    required ColorScheme? cameraSource,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        system?.copyWith(surfaceTint: Colors.transparent) ??
        (isDark ? AppPalettes.dark : AppPalettes.light);
    final dialogColor = system != null
        ? scheme.surfaceContainerHigh
        : (isDark ? AppPalettes.darkDialog : AppPalettes.lightDialog);
    final camera = system != null && cameraSource != null
        ? AppCameraColors(
            selected: cameraSource.primaryContainer,
            onSelected: cameraSource.onPrimaryContainer,
          )
        : (isDark
              ? AppCameraColors.darkFallback
              : AppCameraColors.lightFallback);

    const stadium = StadiumBorder();
    const buttonSize = Size(64, AppSpacing.buttonHeight);
    final textTheme = _textTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: <ThemeExtension<dynamic>>[
        isDark ? AppStatusColors.dark : AppStatusColors.light,
        camera,
        AppColorSource(system: system != null),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          // Dark cards get a 1 px outline, light cards none.
          side: isDark
              ? BorderSide(color: scheme.outlineVariant)
              : BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          disabledBackgroundColor: scheme.onSurface.withValues(alpha: 0.12),
          disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.38),
          minimumSize: buttonSize,
          elevation: 0,
          shape: stadium,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline),
          minimumSize: buttonSize,
          shape: stadium,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(64, AppSpacing.minTouch),
          shape: stadium,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(AppSpacing.minTouch, AppSpacing.minTouch),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll<OutlinedBorder>(stadium),
          side: WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: scheme.outline),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.secondaryContainer
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onSecondaryContainer
                : scheme.onSurface,
          ),
          minimumSize: const WidgetStatePropertyAll<Size>(
            Size(48, AppSpacing.minTouch),
          ),
          textStyle: WidgetStatePropertyAll<TextStyle?>(textTheme.labelLarge),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: _fieldBorder(scheme.outline),
        enabledBorder: _fieldBorder(scheme.outline),
        focusedBorder: _fieldBorder(scheme.primary, width: 2),
        errorBorder: _fieldBorder(scheme.error),
        focusedErrorBorder: _fieldBorder(scheme.error, width: 2),
        disabledBorder: _fieldBorder(scheme.outlineVariant),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: dialogColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: dialogColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.dialog),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      snackBarTheme: SnackBarThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
      ),
    );
  }

  static OutlineInputBorder _fieldBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.field),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  /// The type scale of DESIGN_SPEC section 3.6 (size / line height, weight).
  /// Colours come from the Material 3 typography (they follow `onSurface`).
  static TextTheme _textTheme() {
    TextStyle style(double size, double line, FontWeight weight) => TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      height: line / size,
      fontWeight: weight,
    );
    return TextTheme(
      headlineSmall: style(26, 32, FontWeight.w600),
      titleLarge: style(22, 28, FontWeight.w500),
      titleMedium: style(18, 24, FontWeight.w600),
      bodyLarge: style(16, 24, FontWeight.w400),
      bodyMedium: style(15, 22, FontWeight.w400),
      bodySmall: style(13, 18, FontWeight.w400),
      labelSmall: style(13, 18, FontWeight.w400),
      labelLarge: style(15, 20, FontWeight.w600),
    );
  }
}

/// Tonal button style for the few tonal buttons: the theme gives every filled
/// button the primary-container colours, so a tonal one passes its own
/// (`secondaryContainer`).
abstract final class AppButtonStyles {
  static ButtonStyle tonal(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton.styleFrom(
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
    );
  }
}
