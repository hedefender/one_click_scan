abstract final class RoutePaths {
  static const firstRun = '/first-run';
  static const home = '/home';
  static const settings = '/settings';
  static const scan = '/scan';
  static const scanResult = '/scan/result';
  static const ocrResult = '/scan/ocr';

  /// Hidden: five taps on the app name in Settings (Phase 6.2).
  static const lightDiagnostics = '/settings/light-diagnostics';

  static String initialFor({required bool firstRunCompleted}) {
    return firstRunCompleted ? home : firstRun;
  }
}
