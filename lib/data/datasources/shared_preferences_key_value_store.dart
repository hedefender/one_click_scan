import 'package:shared_preferences/shared_preferences.dart';

import 'key_value_store.dart';

class SharedPreferencesKeyValueStore implements KeyValueStore {
  SharedPreferencesKeyValueStore(this._preferences);

  final SharedPreferences _preferences;

  @override
  String? getString(String key) => _preferences.getString(key);

  @override
  bool? getBool(String key) => _preferences.getBool(key);

  @override
  int? getInt(String key) => _preferences.getInt(key);

  @override
  Future<void> setString(String key, String value) async {
    await _preferences.setString(key, value);
  }

  @override
  Future<void> setBool(String key, bool value) async {
    await _preferences.setBool(key, value);
  }

  @override
  Future<void> setInt(String key, int value) async {
    await _preferences.setInt(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await _preferences.remove(key);
  }
}
