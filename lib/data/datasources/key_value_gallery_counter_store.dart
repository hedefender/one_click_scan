import '../../domain/ports/gallery_counter_store.dart';
import 'key_value_store.dart';

/// [GalleryCounterStore] over the app's key/value store: the date of the last
/// copy and its number.
class KeyValueGalleryCounterStore implements GalleryCounterStore {
  const KeyValueGalleryCounterStore(this._store);

  static const keyDate = 'gallery.counter.date';
  static const keyLast = 'gallery.counter.last';

  final KeyValueStore _store;

  @override
  int nextNumber(String date) {
    if (_store.getString(keyDate) != date) return 1;
    return (_store.getInt(keyLast) ?? 0) + 1;
  }

  @override
  Future<void> markUsed(String date, int number) async {
    await _store.setString(keyDate, date);
    await _store.setInt(keyLast, number);
  }
}
