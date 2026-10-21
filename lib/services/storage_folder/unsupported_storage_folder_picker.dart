import '../../core/errors/app_exceptions.dart';
import '../../domain/entities/storage_folder.dart';
import 'storage_folder_picker.dart';

/// Used on platforms without an implementation yet (iOS, desktop, web).
class UnsupportedStorageFolderPicker implements StorageFolderPicker {
  const UnsupportedStorageFolderPicker();

  @override
  Future<StorageFolder?> pickFolder() {
    throw const StorageFolderException(
      'Folder selection is not supported on this platform yet',
    );
  }

  @override
  Future<bool> hasAccess(StorageFolder folder) async => false;
}
