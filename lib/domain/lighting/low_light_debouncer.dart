import 'light_metric.dart';
import 'lighting_config.dart';

/// Keeps the "low light" mark of the preview from flickering: it changes only
/// when two samples in a row agree (about 0.8 s at the analysis rate).
class LowLightDebouncer {
  bool _low = false;
  bool? _previous;

  /// The mark as it is now.
  bool get isLow => _low;

  /// Feeds one sample; returns the mark after it.
  bool add(LightMetric metric) {
    final sample = LightingConfig.isLowLight(metric);
    if (_previous == sample) _low = sample;
    _previous = sample;
    return _low;
  }

  void reset() {
    _low = false;
    _previous = null;
  }
}
