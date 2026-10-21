import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const Color _seed = Color(0xFF00796B);

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: _seed,
      brightness: Brightness.light,
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: _seed,
      brightness: Brightness.dark,
    );
  }
}
