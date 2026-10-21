import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/core/navigation/route_paths.dart';

void main() {
  test('initial route depends on first run completion', () {
    expect(
      RoutePaths.initialFor(firstRunCompleted: false),
      RoutePaths.firstRun,
    );
    expect(RoutePaths.initialFor(firstRunCompleted: true), RoutePaths.home);
  });
}
