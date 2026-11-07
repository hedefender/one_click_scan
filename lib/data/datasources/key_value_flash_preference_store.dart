import '../../domain/lighting/flash_mode.dart';
import '../../domain/ports/flash_preference_store.dart';
import 'key_value_store.dart';

/// [FlashPreferenceStore] over the app's key/value store. On is written as
/// Auto, so a stored On does not exist and the app never starts with a full
/// flash the user forgot (ADR-030).
class KeyValueFlashPreferenceStore implements FlashPreferenceStore {
  const KeyValueFlashPreferenceStore(this._store);

  static const keyMode = 'camera.flashMode';

  final KeyValueStore _store;

  @override
  FlashMode load() => FlashMode.fromStored(_store.getString(keyMode));

  @override
  Future<void> save(FlashMode mode) =>
      _store.setString(keyMode, mode.storedName);
}
