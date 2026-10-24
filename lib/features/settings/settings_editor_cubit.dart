import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/entities/app_language.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/destination_mode.dart';
import '../../domain/entities/mail_provider_id.dart';
import '../../domain/usecases/load_settings.dart';
import '../../domain/usecases/update_settings.dart';
import '../../services/storage_folder/storage_folder_picker.dart';
import 'settings_editor_state.dart';

/// Editing session for the settings screen. The app-wide `SettingsCubit`
/// keeps mirroring the stored settings; this cubit only owns the unsaved
/// e-mail draft and the screen's transient status.
class SettingsEditorCubit extends Cubit<SettingsEditorState> {
  SettingsEditorCubit({
    required this._loadSettings,
    required this._updateSettings,
    required this._folderPicker,
    required this._logger,
  }) : super(const SettingsEditorState());

  final LoadSettings _loadSettings;
  final UpdateSettings _updateSettings;
  final StorageFolderPicker _folderPicker;
  final AppLogger _logger;

  Future<void> start() async {
    final settings = await _loadSettings();
    if (isClosed) return;
    emit(_draftFrom(settings, folderStatus: state.folderStatus));
    await _refreshFolderAccess(settings);
  }

  // --- Saved immediately ---------------------------------------------------

  Future<void> selectLanguage(AppLanguage language) {
    return _applyImmediately((current) => current.copyWith(language: language));
  }

  Future<void> setSaveToGallery(bool value) {
    return _applyImmediately(
      (current) => current.copyWith(saveToGallery: value),
    );
  }

  /// The OCR language pack. Saved at once, like the language.
  Future<void> selectOcrPack(String packId) {
    return _applyImmediately((current) => current.copyWith(ocrPackId: packId));
  }

  Future<void> changeFolder() async {
    if (state.folderStatus == SettingsFolderStatus.picking) return;
    emit(state.copyWith(folderStatus: SettingsFolderStatus.picking));
    try {
      final folder = await _folderPicker.pickFolder();
      if (isClosed) return;
      if (folder == null) {
        emit(state.copyWith(folderStatus: SettingsFolderStatus.idle));
        return;
      }
      final updated = await _updateSettings(
        (current) => current.copyWith(storageFolder: folder),
      );
      if (isClosed) return;
      emit(
        state.copyWith(
          saved: updated,
          folderStatus: SettingsFolderStatus.idle,
          folderAccessLost: false,
        ),
      );
      await _refreshFolderAccess(updated);
    } catch (error, stackTrace) {
      _logger.error('Storage folder selection failed', error, stackTrace);
      if (isClosed) return;
      emit(state.copyWith(folderStatus: SettingsFolderStatus.failed));
    }
  }

  // --- E-mail draft --------------------------------------------------------

  void selectProvider(MailProviderId provider) {
    emit(state.copyWith(provider: provider));
  }

  void setSenderAccount(String value) {
    emit(state.copyWith(senderAccount: value));
  }

  void selectDestinationMode(DestinationMode mode) {
    emit(state.copyWith(destinationMode: mode));
  }

  void setCustomDestination(String value) {
    emit(state.copyWith(customDestination: value));
  }

  /// Persists the e-mail draft if it is valid and changed.
  Future<void> save() async {
    final snapshot = state;
    if (!snapshot.canSave) return;
    final updated = await _updateSettings(
      (current) => current.copyWith(
        mailProvider: snapshot.provider,
        senderAccount: snapshot.senderAccount.trim(),
        destinationMode: snapshot.destinationMode,
        customDestination: snapshot.normalizedCustomDestination,
      ),
    );
    if (isClosed) return;
    emit(state.copyWith(saved: updated, justSaved: true));
  }

  /// Throws away the unsaved e-mail draft.
  void discardChanges() {
    final current = state.saved;
    if (current == null) return;
    emit(
      _draftFrom(
        current,
        folderStatus: state.folderStatus,
        folderAccessLost: state.folderAccessLost,
      ),
    );
  }

  // --- Internals -----------------------------------------------------------

  Future<void> _applyImmediately(
    AppSettings Function(AppSettings current) transform,
  ) async {
    final updated = await _updateSettings(transform);
    if (isClosed) return;
    emit(state.copyWith(saved: updated));
  }

  Future<void> _refreshFolderAccess(AppSettings settings) async {
    final folder = settings.storageFolder;
    if (folder == null) return;
    try {
      final granted = await _folderPicker.hasAccess(folder);
      if (isClosed) return;
      emit(state.copyWith(folderAccessLost: !granted));
    } catch (error, stackTrace) {
      _logger.error('Storage folder access check failed', error, stackTrace);
    }
  }

  SettingsEditorState _draftFrom(
    AppSettings settings, {
    required SettingsFolderStatus folderStatus,
    bool folderAccessLost = false,
  }) {
    return SettingsEditorState(
      saved: settings,
      provider: settings.mailProvider,
      senderAccount: settings.senderAccount ?? '',
      destinationMode: settings.destinationMode,
      customDestination: settings.customDestination ?? '',
      folderStatus: folderStatus,
      folderAccessLost: folderAccessLost,
    );
  }
}
