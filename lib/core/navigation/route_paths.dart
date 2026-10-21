abstract final class RoutePaths {
  static const firstRun = '/first-run';
  static const home = '/home';

  static String initialFor({required bool firstRunCompleted}) {
    return firstRunCompleted ? home : firstRun;
  }
}
