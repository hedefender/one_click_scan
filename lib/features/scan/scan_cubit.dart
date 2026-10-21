import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/entities/scan_mode.dart';
import '../../domain/entities/storage_folder.dart';
import '../../domain/usecases/load_settings.dart';
import '../../domain/usecases/store_scan_pages.dart';
import '../../services/camera/camera_service.dart';
import '../../services/scan_files/scan_temp_store.dart';
import '../../services/storage_folder/storage_folder_picker.dart';
import 'scan_state.dart';

/// State machine of one scan: check folder, open camera, take one or many
/// pages (kept in the cache), then store them in the user's folder.
class ScanCubit extends Cubit<ScanState> {
  ScanCubit({
    required this._loadSettings,
    required this._folderPicker,
    required this._camera,
    required this._storeScanPages,
    required this._tempStore,
    required this._logger,
  }) : super(const ScanState());

  final LoadSettings _loadSettings;
  final StorageFolderPicker _folderPicker;
  final CameraService _camera;
  final StoreScanPages _storeScanPages;
  final ScanTempStore _tempStore;
  final AppLogger _logger;

  /// Entry point (and "try again" after a denied permission or a missing
  /// folder). Nothing starts without an accessible folder.
  Future<void> start() async {
    emit(state.copyWith(phase: ScanPhase.starting));
    final settings = await _loadSettings();
    final folder = settings.storageFolder;
    final accessible = folder != null && await _hasAccess(folder);
    if (isClosed) return;
    if (!accessible) {
      emit(state.copyWith(phase: ScanPhase.folderUnavailable));
      return;
    }
    await _openCamera();
  }

  void setMode(ScanMode mode) {
    if (!state.canChangeMode) return;
    emit(state.copyWith(mode: mode));
  }

  Future<void> capture() async {
    if (!state.canCapture) return;
    emit(state.copyWith(phase: ScanPhase.capturing, captureFailed: false));
    try {
      final page = await _camera.capture(order: state.pages.length + 1);
      if (isClosed) {
        await _tempStore.delete([page.path]);
        return;
      }
      emit(
        state.copyWith(phase: ScanPhase.ready, pages: [...state.pages, page]),
      );
    } on CameraCaptureException catch (error, stackTrace) {
      _logger.error('Capture failed', error, stackTrace);
      if (isClosed) return;
      emit(state.copyWith(phase: ScanPhase.ready, captureFailed: true));
      return;
    }
    if (state.mode == ScanMode.single) await save();
  }

  /// Multi-page: removes the last shot.
  Future<void> deleteLast() async {
    if (state.phase != ScanPhase.ready || !state.hasPages) return;
    final removed = state.pages.last;
    emit(
      state.copyWith(
        pages: state.pages.sublist(0, state.pages.length - 1),
        captureFailed: false,
      ),
    );
    await _tempStore.delete([removed.path]);
  }

  /// Multi-page "Done".
  Future<void> finish() async {
    if (!state.canFinish) return;
    await save();
  }

  /// Stores the pages. Also the "try again" of a failed save: the pages are
  /// still in the cache, nothing is lost.
  Future<void> save() async {
    final canRun =
        state.hasPages &&
        (state.phase == ScanPhase.ready ||
            state.phase == ScanPhase.capturing ||
            state.phase == ScanPhase.saveFailed);
    if (!canRun) return;
    emit(state.copyWith(phase: ScanPhase.saving));

    try {
      final settings = await _loadSettings();
      final folder = settings.storageFolder;
      if (folder == null || !await _hasAccess(folder)) {
        if (isClosed) return;
        emit(state.copyWith(phase: ScanPhase.folderUnavailable));
        return;
      }
      final stored = await _storeScanPages(
        pages: state.pages,
        folder: folder,
        saveToGallery: settings.saveToGallery,
      );
      if (isClosed) return;
      await _camera.close();
      emit(state.copyWith(phase: ScanPhase.saved, result: stored));
    } on ScanStoreException catch (error, stackTrace) {
      _logger.error('Storing the scan failed', error, stackTrace);
      if (isClosed) return;
      if (error.failure == ScanStoreFailure.noAccess) {
        emit(state.copyWith(phase: ScanPhase.folderUnavailable));
      } else {
        emit(state.copyWith(phase: ScanPhase.saveFailed));
      }
    } catch (error, stackTrace) {
      _logger.error('Storing the scan failed unexpectedly', error, stackTrace);
      if (isClosed) return;
      emit(state.copyWith(phase: ScanPhase.saveFailed));
    }
  }

  /// "Try again" from the folder warning, after the user fixed the folder in
  /// Settings. Keeps the pages already taken.
  Future<void> retryAfterFolderFix() async {
    if (state.phase != ScanPhase.folderUnavailable) return;
    await start();
    // A single-page scan saves right after the shot; if that save was
    // interrupted by the folder problem, finish it now.
    if (state.phase == ScanPhase.ready &&
        state.mode == ScanMode.single &&
        state.hasPages) {
      await save();
    }
  }

  /// "Try again" after a denied camera permission.
  Future<void> retryCamera() async {
    if (state.phase != ScanPhase.permissionDenied &&
        state.phase != ScanPhase.cameraUnavailable) {
      return;
    }
    await start();
  }

  Future<void> openAppSettings() => _camera.openAppSettings();

  /// Leaving the scan: nothing of an unfinished scan may stay behind.
  Future<void> cancel() async {
    await _discardUnsavedPages();
    await _camera.close();
  }

  /// Cache files of pages that were never stored. After a successful save the
  /// result screen still shows them as thumbnails and deletes them itself.
  Future<void> _discardUnsavedPages() async {
    if (state.phase == ScanPhase.saved || !state.hasPages) return;
    final paths = [for (final page in state.pages) page.path];
    if (!isClosed) emit(state.copyWith(pages: const []));
    await _tempStore.delete(paths);
  }

  /// App went to the background: release the camera.
  Future<void> onBackground() async {
    if (state.phase != ScanPhase.ready) return;
    emit(state.copyWith(phase: ScanPhase.paused));
    await _camera.close();
  }

  /// App came back: reopen the camera, or re-check a denied permission (the
  /// user may have granted it in the system settings).
  Future<void> onForeground() async {
    switch (state.phase) {
      case ScanPhase.paused:
        await _openCamera();
      case ScanPhase.permissionDenied:
        await retryCamera();
      case _:
        break;
    }
  }

  Future<void> _openCamera() async {
    final result = await _camera.open();
    if (isClosed) {
      await _camera.close();
      return;
    }
    emit(
      state.copyWith(
        phase: switch (result) {
          CameraOpenResult.ready => ScanPhase.ready,
          CameraOpenResult.permissionDenied => ScanPhase.permissionDenied,
          CameraOpenResult.unavailable => ScanPhase.cameraUnavailable,
        },
      ),
    );
  }

  Future<bool> _hasAccess(StorageFolder folder) async {
    try {
      return await _folderPicker.hasAccess(folder);
    } catch (error, stackTrace) {
      _logger.error('Storage folder access check failed', error, stackTrace);
      return false;
    }
  }

  @override
  Future<void> close() async {
    await _discardUnsavedPages();
    await _camera.close();
    return super.close();
  }
}
