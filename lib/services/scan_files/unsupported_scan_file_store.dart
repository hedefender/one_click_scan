import '../../core/errors/app_exceptions.dart';
import '../../domain/entities/storage_folder.dart';
import '../../domain/ports/scan_file_store.dart';
import 'scan_temp_store.dart';

/// Used on platforms without an implementation, and as the container default.
class UnsupportedScanFileStore implements ScanFileStore {
  const UnsupportedScanFileStore();

  static const _failure = ScanStoreException(
    ScanStoreFailure.unknown,
    'Not supported on this platform',
  );

  @override
  Future<void> ensureSubfolder(StorageFolder folder, String name) {
    throw _failure;
  }

  @override
  Future<void> ensureNoMedia(StorageFolder folder, String subfolder) {
    throw _failure;
  }

  @override
  Future<List<String>> listFileNames(StorageFolder folder, String subfolder) {
    throw _failure;
  }

  @override
  Future<String> copyToFolder({
    required StorageFolder folder,
    required String subfolder,
    required String fileName,
    required String mimeType,
    required String sourcePath,
  }) {
    throw _failure;
  }

  @override
  Future<void> deleteFile({
    required StorageFolder folder,
    required String subfolder,
    required String fileName,
  }) {
    throw _failure;
  }

  @override
  Future<void> deleteByUri(String uri) {
    throw _failure;
  }
}

class NoopScanTempStore implements ScanTempStore {
  const NoopScanTempStore();

  @override
  Future<void> delete(Iterable<String> paths) async {}

  @override
  Future<void> purgeAll() async {}
}
