abstract final class RoutePaths {
  static const firstRun = '/first-run';
  static const home = '/home';
  static const settings = '/settings';
  static const scan = '/scan';
  static const scanResult = '/scan/result';
  static const ocrResult = '/scan/ocr';

  /// Help (Settings) and the guide page it can show again (Phase 6.3).
  static const help = '/settings/help';
  static const helpGuide = '/settings/help/guide';

  /// About and the feedback button (Phase 6.5).
  static const about = '/settings/about';

  /// Hidden: five taps on the app name in Settings (Phase 6.2).
  static const lightDiagnostics = '/settings/light-diagnostics';

  static String initialFor({required bool firstRunCompleted}) {
    return firstRunCompleted ? home : firstRun;
  }
}
