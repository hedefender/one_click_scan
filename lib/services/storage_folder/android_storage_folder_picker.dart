import 'package:flutter/services.dart';

import '../../core/errors/app_exceptions.dart';
import '../../domain/entities/storage_folder.dart';
import 'storage_folder_picker.dart';

/// Talks to `MainActivity.kt` (see `android_overlay/`).
class AndroidStorageFolderPicker implements StorageFolderPicker {
  AndroidStorageFolderPicker({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Must match `CHANNEL` in MainActivity.kt.
  static const channelName = 'com.example.one_click_scan/storage';

  final MethodChannel _channel;

  @override
  Future<StorageFolder?> pickFolder() async {
    final Map<String, String>? result;
    try {
      result = await _channel.invokeMapMethod<String, String>('pickFolder');
    } on PlatformException catch (error) {
      throw StorageFolderException(error.message ?? error.code);
    }
    if (result == null) return null;

    final uri = result['uri'];
    if (uri == null || uri.isEmpty) {
      throw const StorageFolderException('Picker returned no folder URI');
    }
    final name = result['name'];
    return StorageFolder(
      uri: uri,
      name: (name == null || name.isEmpty) ? uri : name,
    );
  }

  @override
  Future<bool> hasAccess(StorageFolder folder) async {
    try {
      final granted = await _channel.invokeMethod<bool>(
        'hasAccess',
        <String, String>{'uri': folder.uri},
      );
      return granted ?? false;
    } on PlatformException {
      return false;
    }
  }
}
