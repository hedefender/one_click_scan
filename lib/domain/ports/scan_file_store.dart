import '../entities/storage_folder.dart';

/// Writes into the user's chosen folder (Android: SAF tree URI).
///
/// File bytes never travel through Dart: the copy runs natively, from a
/// temporary file to the folder. Every method throws `ScanStoreException`.
abstract interface class ScanFileStore {
  /// Creates `./<name>` inside [folder] when it is missing.
  Future<void> ensureSubfolder(StorageFolder folder, String name);

  /// Makes sure `./<subfolder>` holds an empty `.nomedia` file, so the system
  /// media index (and with it the Gallery and Google Photos) ignores the
  /// folder. Idempotent: does nothing when the file is already there.
  Future<void> ensureNoMedia(StorageFolder folder, String subfolder);

  /// File names inside `./<subfolder>`. Empty when the sub-folder is missing.
  Future<List<String>> listFileNames(StorageFolder folder, String subfolder);

  /// Copies [sourcePath] to `./<subfolder>/<fileName>` and returns the
  /// document URI of the new file (what a viewer is given). Fails with
  /// `ScanStoreFailure.exists` instead of renaming when the name is taken.
  Future<String> copyToFolder({
    required StorageFolder folder,
    required String subfolder,
    required String fileName,
    required String mimeType,
    required String sourcePath,
  });

  /// Deletes `./<subfolder>/<fileName>`. Used to roll back a partly written
  /// scan. Does nothing when the file is already gone.
  Future<void> deleteFile({
    required StorageFolder folder,
    required String subfolder,
    required String fileName,
  });
}
