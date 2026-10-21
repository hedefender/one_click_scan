import '../../domain/entities/storage_folder.dart';

/// Lets the user choose a visible folder and checks it is still usable.
///
/// Android: Storage Access Framework tree URI with persisted permission.
/// iOS (future): security-scoped bookmark. Implementations live behind this
/// interface so the rest of the app stays platform independent.
abstract interface class StorageFolderPicker {
  /// Returns `null` when the user cancels the picker.
  /// Throws `StorageFolderException` when the platform fails.
  Future<StorageFolder?> pickFolder();

  /// Whether read/write access to [folder] is still granted.
  Future<bool> hasAccess(StorageFolder folder);
}
