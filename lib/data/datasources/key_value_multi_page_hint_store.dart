import '../../domain/ports/multi_page_hint_store.dart';
import 'key_value_store.dart';

/// [MultiPageHintStore] over the app's key/value store. Only a flag: no
/// content of the user is kept.
class KeyValueMultiPageHintStore implements MultiPageHintStore {
  const KeyValueMultiPageHintStore(this._store);

  static const keySeen = 'hints.multiPageSeen';

  final KeyValueStore _store;

  @override
  bool get seen => _store.getBool(keySeen) ?? false;

  @override
  Future<void> markSeen() => _store.setBool(keySeen, true);
}
