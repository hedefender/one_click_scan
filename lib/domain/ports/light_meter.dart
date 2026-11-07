import '../lighting/light_metric.dart';

/// Measures the brightness of a picture file (the shot, after the capture).
/// Never throws; null when it could not be measured. Not on the UI isolate.
abstract interface class LightMeter {
  Future<LightMetric?> measureFile(String path);
}

/// Used where nothing can be measured (tests, other platforms): no shot is
/// ever called dark.
class NoLightMeter implements LightMeter {
  const NoLightMeter();

  @override
  Future<LightMetric?> measureFile(String path) async => null;
}
