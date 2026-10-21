import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/usecases/load_settings.dart';
import '../../services/storage_folder/storage_folder_picker.dart';

/// Whether the stored storage folder is still usable. `true` means access was
/// lost and the user must pick the folder again.
class HomeCubit extends Cubit<bool> {
  HomeCubit({
    required this._loadSettings,
    required this._folderPicker,
    required this._logger,
  }) : super(false);

  final LoadSettings _loadSettings;
  final StorageFolderPicker _folderPicker;
  final AppLogger _logger;

  Future<void> checkFolderAccess() async {
    try {
      final folder = (await _loadSettings()).storageFolder;
      if (folder == null) {
        if (!isClosed) emit(false);
        return;
      }
      final granted = await _folderPicker.hasAccess(folder);
      if (!isClosed) emit(!granted);
    } catch (error, stackTrace) {
      _logger.error('Storage folder access check failed', error, stackTrace);
    }
  }
}
