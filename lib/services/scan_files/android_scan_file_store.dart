import 'package:flutter/services.dart';

import '../../core/errors/app_exceptions.dart';
import '../../domain/entities/storage_folder.dart';
import '../../domain/ports/scan_file_store.dart';

/// Talks to `ScanFilesHandler.kt` (see `android_overlay/`).
class AndroidScanFileStore implements ScanFileStore {
  AndroidScanFileStore({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Must match `CHANNEL` in ScanFilesHandler.kt.
  static const channelName = 'com.example.one_click_scan/scan_files';

  final MethodChannel _channel;

  @override
  Future<void> ensureSubfolder(StorageFolder folder, String name) {
    return _invoke<void>('ensureSubfolder', <String, String>{
      'treeUri': folder.uri,
      'name': name,
    });
  }

  @override
  Future<void> ensureNoMedia(StorageFolder folder, String subfolder) {
    return _invoke<void>('ensureNoMedia', <String, String>{
      'treeUri': folder.uri,
      'subfolder': subfolder,
    });
  }

  @override
  Future<List<String>> listFileNames(
    StorageFolder folder,
    String subfolder,
  ) async {
    final names = await _invoke<List<Object?>>(
      'listFileNames',
      <String, String>{'treeUri': folder.uri, 'subfolder': subfolder},
    );
    return <String>[...?names?.whereType<String>()];
  }

  @override
  Future<String> copyToFolder({
    required StorageFolder folder,
    required String subfolder,
    required String fileName,
    required String mimeType,
    required String sourcePath,
  }) async {
    final uri = await _invoke<String>('copyToFolder', <String, String>{
      'treeUri': folder.uri,
      'subfolder': subfolder,
      'fileName': fileName,
      'mimeType': mimeType,
      'sourcePath': sourcePath,
    });
    if (uri == null) {
      throw const ScanStoreException(ScanStoreFailure.unknown, 'no uri');
    }
    return uri;
  }

  @override
  Future<void> deleteFile({
    required StorageFolder folder,
    required String subfolder,
    required String fileName,
  }) {
    return _invoke<void>('deleteFile', <String, String>{
      'treeUri': folder.uri,
      'subfolder': subfolder,
      'fileName': fileName,
    });
  }

  @override
  Future<void> deleteByUri(String uri) {
    return _invoke<void>('deleteDocument', <String, String>{'uri': uri});
  }

  Future<T?> _invoke<T>(String method, Map<String, String> arguments) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw ScanStoreException(_failureFor(error.code), error.code);
    } on MissingPluginException {
      throw const ScanStoreException(ScanStoreFailure.unknown, 'no handler');
    }
  }

  /// Error codes defined in ScanFilesHandler.kt.
  static ScanStoreFailure _failureFor(String code) {
    return switch (code) {
      'no_access' => ScanStoreFailure.noAccess,
      'exists' => ScanStoreFailure.exists,
      'write_failed' => ScanStoreFailure.writeFailed,
      'source_missing' => ScanStoreFailure.sourceMissing,
      _ => ScanStoreFailure.unknown,
    };
  }
}
