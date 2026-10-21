/// Tiny synchronous-read key/value abstraction so settings code does not
/// depend on a plugin and can be unit tested with an in-memory fake.
abstract interface class KeyValueStore {
  String? getString(String key);

  bool? getBool(String key);

  int? getInt(String key);

  Future<void> setString(String key, String value);

  Future<void> setBool(String key, bool value);

  Future<void> setInt(String key, int value);

  Future<void> remove(String key);
}
