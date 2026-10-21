import '../../domain/entities/app_language.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/destination_mode.dart';
import '../../domain/entities/mail_provider_id.dart';
import '../../domain/entities/storage_folder.dart';
import 'key_value_store.dart';

/// Maps [AppSettings] to flat key/value pairs.
///
/// Reads are forgiving: missing or unknown values fall back to defaults, so a
/// newer or corrupted store can never crash the app at startup.
class SettingsLocalDataSource {
  SettingsLocalDataSource({
    required this._store,
    required this.schemaVersion,
    required this.defaultLanguage,
  });

  static const keySchemaVersion = 'settings.schemaVersion';
  static const keyLanguage = 'settings.language';
  static const keyFirstRunCompleted = 'settings.firstRunCompleted';
  static const keyStorageUri = 'settings.storage.uri';
  static const keyStorageName = 'settings.storage.name';
  static const keyMailProvider = 'settings.mail.provider';
  static const keyMailSender = 'settings.mail.sender';
  static const keyDestinationMode = 'settings.mail.destinationMode';
  static const keyCustomDestination = 'settings.mail.customDestination';
  static const keySaveToGallery = 'settings.gallery.save';

  final KeyValueStore _store;
  final int schemaVersion;
  final AppLanguage defaultLanguage;

  AppSettings read() {
    final folderUri = _store.getString(keyStorageUri);
    final folderName = _store.getString(keyStorageName);

    return AppSettings(
      language:
          AppLanguage.fromCode(_store.getString(keyLanguage)) ??
          defaultLanguage,
      firstRunCompleted: _store.getBool(keyFirstRunCompleted) ?? false,
      storageFolder: (folderUri == null || folderUri.isEmpty)
          ? null
          : StorageFolder(
              uri: folderUri,
              name: (folderName == null || folderName.isEmpty)
                  ? folderUri
                  : folderName,
            ),
      mailProvider: _enumByName(
        MailProviderId.values,
        _store.getString(keyMailProvider),
      ),
      senderAccount: _store.getString(keyMailSender),
      destinationMode:
          _enumByName(
            DestinationMode.values,
            _store.getString(keyDestinationMode),
          ) ??
          DestinationMode.own,
      customDestination: _store.getString(keyCustomDestination),
      saveToGallery: _store.getBool(keySaveToGallery) ?? false,
    );
  }

  Future<void> write(AppSettings settings) async {
    await _store.setInt(keySchemaVersion, schemaVersion);
    await _store.setString(keyLanguage, settings.language.code);
    await _store.setBool(keyFirstRunCompleted, settings.firstRunCompleted);
    await _setOrRemove(keyStorageUri, settings.storageFolder?.uri);
    await _setOrRemove(keyStorageName, settings.storageFolder?.name);
    await _setOrRemove(keyMailProvider, settings.mailProvider?.name);
    await _setOrRemove(keyMailSender, settings.senderAccount);
    await _store.setString(keyDestinationMode, settings.destinationMode.name);
    await _setOrRemove(keyCustomDestination, settings.customDestination);
    await _store.setBool(keySaveToGallery, settings.saveToGallery);
  }

  Future<void> _setOrRemove(String key, String? value) {
    if (value == null) return _store.remove(key);
    return _store.setString(key, value);
  }

  static T? _enumByName<T extends Enum>(List<T> values, String? name) {
    if (name == null) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
