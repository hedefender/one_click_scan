import 'package:flutter/material.dart';

/// Spacing scale, sizes and radii (DESIGN_SPEC §3.7 and §3.8).
abstract final class AppSpacing {
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s48 = 48;

  /// Horizontal margin of a screen.
  static const double screen = 24;

  /// Gap between cards and between sections.
  static const double cardGap = 12;
  static const double sectionGap = 24;

  static const double buttonHeight = 56;
  static const double minTouch = 48;
}

abstract final class AppRadius {
  static const double field = 16;
  static const double card = 24;
  static const double dialog = 28;
  static const double thumbnail = 12;

  static BorderRadius get thumbnailBorder => BorderRadius.circular(thumbnail);
}
