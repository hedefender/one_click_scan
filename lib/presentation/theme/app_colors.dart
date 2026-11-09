import 'package:flutter/material.dart';

/// The fallback palettes of the app (DESIGN_SPEC §3.3). They are used when the
/// system gives no colours (Android older than 12 or a maker without support).
/// Widgets never read these values: they read the roles of the `ColorScheme`.
abstract final class AppPalettes {
  static const Color lightSeed = Color(0xFF4D6410);
  static const Color darkSeed = Color(0xFFCBBBE6);

  /// Dialog background of the fallback palettes.
  static const Color lightDialog = Color(0xFFF7F8EF);
  static const Color darkDialog = Color(0xFF221E2E);

  static final ColorScheme light =
      ColorScheme.fromSeed(
        seedColor: lightSeed,
        brightness: Brightness.light,
      ).copyWith(
        primary: const Color(0xFF4D6410),
        onPrimary: const Color(0xFFFFFFFF),
        primaryContainer: const Color(0xFFD7EF6C),
        onPrimaryContainer: const Color(0xFF1C2804),
        secondaryContainer: const Color(0xFFE4F2A4),
        onSecondaryContainer: const Color(0xFF243306),
        surface: const Color(0xFFF3F6E8),
        surfaceContainer: const Color(0xFFE6ECD6),
        surfaceContainerHighest: const Color(0xFFDBE3C6),
        onSurface: const Color(0xFF1C1E14),
        onSurfaceVariant: const Color(0xFF5A5E4C),
        outline: const Color(0xFF7A7E66),
        outlineVariant: const Color(0xFFC9CDB6),
        error: const Color(0xFF9D2F32),
        onError: const Color(0xFFFFFFFF),
        surfaceTint: Colors.transparent,
      );

  static final ColorScheme dark =
      ColorScheme.fromSeed(
        seedColor: darkSeed,
        brightness: Brightness.dark,
      ).copyWith(
        primary: const Color(0xFFCBBBE6),
        onPrimary: const Color(0xFF2B2342),
        primaryContainer: const Color(0xFF3F3658),
        onPrimaryContainer: const Color(0xFFE4DCF2),
        secondaryContainer: const Color(0xFF2A2440),
        onSecondaryContainer: const Color(0xFFDDD4F0),
        surface: const Color(0xFF121016),
        surfaceContainer: const Color(0xFF1A1722),
        surfaceContainerHighest: const Color(0xFF242033),
        onSurface: const Color(0xFFD0C9DC),
        onSurfaceVariant: const Color(0xFF9B93AB),
        outline: const Color(0xFF716A8C),
        outlineVariant: const Color(0xFF3A334C),
        error: const Color(0xFFE3B4B8),
        onError: const Color(0xFF3A1418),
        surfaceTint: Colors.transparent,
      );
}

/// Status colours that do not depend on the colour source (DESIGN_SPEC §3.4).
/// The warning stays amber in every theme, also with system colours. Success
/// and failure use `ColorScheme.primary` and `ColorScheme.error`.
@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
  });

  static const AppStatusColors light = AppStatusColors(
    warning: Color(0xFFE8B53A),
    onWarning: Color(0xFF2C2106),
    warningContainer: Color(0xFFF6E4AE),
    onWarningContainer: Color(0xFF2C2106),
  );

  static const AppStatusColors dark = AppStatusColors(
    warning: Color(0xFF6A5738),
    onWarning: Color(0xFFF0E2C8),
    warningContainer: Color(0xFF3A3226),
    onWarningContainer: Color(0xFFF0E2C8),
  );

  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  @override
  AppStatusColors copyWith({
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
  }) {
    return AppStatusColors(
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
    );
  }

  @override
  AppStatusColors lerp(ThemeExtension<AppStatusColors>? other, double t) {
    if (other is! AppStatusColors) return this;
    return AppStatusColors(
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
    );
  }
}

/// The dark "chrome" of the camera screens (DESIGN_SPEC §3.5). Camera content
/// can be bright or dark, so the controls over it are dark in every theme.
@immutable
class AppCameraColors extends ThemeExtension<AppCameraColors> {
  const AppCameraColors({required this.selected, required this.onSelected});

  /// Behind the controls area.
  static const Color background = Color(0xFF0E0E10);

  /// Chips and buttons: white 12 % over the black.
  static const Color control = Color(0x1FFFFFFF);

  /// Text and icons, and the ring of the capture button.
  static const Color content = Color(0xFFE8E8EA);

  /// Over the camera picture itself (a panel on the preview).
  static const Color overlay = Color(0xB30E0E10);

  /// A round control that floats over the picture (white 12 % over the black).
  static const Color floating = Color(0xE02B2B2D);

  static const AppCameraColors lightFallback = AppCameraColors(
    selected: Color(0xFFD7EF6C),
    onSelected: Color(0xFF1C2804),
  );

  static const AppCameraColors darkFallback = AppCameraColors(
    selected: Color(0xFF5C4D82),
    onSelected: Color(0xFFE4DCF2),
  );

  /// Selected element (mode segment, flash On).
  final Color selected;
  final Color onSelected;

  @override
  AppCameraColors copyWith({Color? selected, Color? onSelected}) {
    return AppCameraColors(
      selected: selected ?? this.selected,
      onSelected: onSelected ?? this.onSelected,
    );
  }

  @override
  AppCameraColors lerp(ThemeExtension<AppCameraColors>? other, double t) {
    if (other is! AppCameraColors) return this;
    return AppCameraColors(
      selected: Color.lerp(selected, other.selected, t)!,
      onSelected: Color.lerp(onSelected, other.onSelected, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  AppStatusColors get statusColors =>
      Theme.of(this).extension<AppStatusColors>() ?? AppStatusColors.light;

  AppCameraColors get cameraColors =>
      Theme.of(this).extension<AppCameraColors>() ??
      AppCameraColors.lightFallback;
}
