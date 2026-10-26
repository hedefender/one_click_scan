import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/entities/mail_provider_id.dart';
import '../../domain/ports/mail_credential_store.dart';

/// One string under one key, in secure storage. The plugin sits behind this so
/// the store can be tested without a device.
abstract interface class SecureStringStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// `flutter_secure_storage` on Android: the value is encrypted with a key of
/// the Android Keystore. The app is excluded from Android backups
/// (`allowBackup="false"`, ADR-021), which is what the plugin's own README
/// asks for.
class PluginSecureStringStore implements SecureStringStore {
  const PluginSecureStringStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// The password of the mail account in secure storage, as ONE value (provider,
/// account and password together), so the account is not in the clear in a key
/// name. It is never put in the key/value store and never logged: a failure
/// logs the kind of the error only.
class SecureMailCredentialStore implements MailCredentialStore {
  SecureMailCredentialStore({required this._store, required this._logger});

  /// The key of the one stored value.
  static const key = 'mail.credentials.v1';

  final SecureStringStore _store;
  final AppLogger _logger;

  @override
  Future<StoredMailSecret?> read() async {
    try {
      final raw = await _store.read(key);
      if (raw == null) return null;
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final provider = _providerByName(json['provider']);
      final account = json['account'];
      final secret = json['secret'];
      if (provider == null ||
          account is! String ||
          secret is! String ||
          secret.isEmpty) {
        return null;
      }
      return StoredMailSecret(
        provider: provider,
        accountEmail: account,
        secret: secret,
      );
    } catch (error) {
      // A value that cannot be read (for example a key lost after a restore)
      // is the same as no password: the user enters it again.
      _logger.error(
        'The stored mail password could not be read',
        error.runtimeType,
      );
      return null;
    }
  }

  @override
  Future<void> write(StoredMailSecret secret) async {
    await _store.write(
      key,
      jsonEncode(<String, String>{
        'provider': secret.provider.name,
        'account': secret.accountEmail,
        'secret': secret.secret,
      }),
    );
  }

  @override
  Future<void> delete() async {
    try {
      await _store.delete(key);
    } catch (error) {
      _logger.error(
        'The stored mail password could not be deleted',
        error.runtimeType,
      );
      rethrow;
    }
  }

  static MailProviderId? _providerByName(Object? name) {
    for (final value in MailProviderId.values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
