import '../lighting/flash_mode.dart';

/// Where the choice of the flash is remembered.
abstract interface class FlashPreferenceStore {
  /// The remembered mode. Never [FlashMode.on] (see [FlashMode.storedName]).
  FlashMode load();

  /// Remembers [mode] by the rule of [FlashMode.storedName]: Off and Auto as
  /// they are, On as Auto.
  Future<void> save(FlashMode mode);
}
