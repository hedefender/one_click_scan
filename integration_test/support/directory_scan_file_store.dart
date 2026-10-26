import 'dart:io';

import 'package:one_click_scan/core/errors/app_exceptions.dart';
import 'package:one_click_scan/domain/entities/storage_folder.dart';
import 'package:one_click_scan/domain/ports/scan_file_store.dart';

/// The user's folder as a real directory on the emulator (the system folder
/// picker cannot be driven without a person, so the integration tests cannot
/// get a real SAF tree). Files are really copied, so the PDFs that come out can
/// be read back and pulled to the PC for inspection.
class DirectoryScanFileStore implements ScanFileStore {
  DirectoryScanFileStore(this.root);

  final Directory root;

  /// Make every copy into this sub-folder fail with [failure].
  String? failSubfolder;
  ScanStoreFailure failure = ScanStoreFailure.writeFailed;

  Directory _dir(String sub) => Directory('${root.path}/$sub');

  List<String> files(String sub) => _dir(sub).existsSync()
      ? [
          for (final e in _dir(sub).listSync())
            if (e is File) e.uri.pathSegments.last,
        ]
      : <String>[];

  @override
  Future<void> ensureSubfolder(StorageFolder folder, String name) async {
    _dir(name).createSync(recursive: true);
  }

  @override
  Future<void> ensureNoMedia(StorageFolder folder, String subfolder) async {
    File('${_dir(subfolder).path}/.nomedia').createSync(recursive: true);
  }

  @override
  Future<List<String>> listFileNames(
    StorageFolder folder,
    String subfolder,
  ) async => files(subfolder);

  @override
  Future<String> copyToFolder({
    required StorageFolder folder,
    required String subfolder,
    required String fileName,
    required String mimeType,
    required String sourcePath,
  }) async {
    if (failSubfolder == subfolder) throw ScanStoreException(failure);
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw const ScanStoreException(ScanStoreFailure.sourceMissing);
    }
    final target = File('${_dir(subfolder).path}/$fileName');
    if (target.existsSync()) {
      throw const ScanStoreException(ScanStoreFailure.exists);
    }
    target.parent.createSync(recursive: true);
    source.copySync(target.path);
    return target.uri.toString();
  }

  @override
  Future<void> deleteFile({
    required StorageFolder folder,
    required String subfolder,
    required String fileName,
  }) async {
    final target = File('${_dir(subfolder).path}/$fileName');
    if (target.existsSync()) target.deleteSync();
  }
}
