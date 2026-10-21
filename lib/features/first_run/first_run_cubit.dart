import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/entities/app_language.dart';
import '../../domain/entities/destination_mode.dart';
import '../../domain/entities/mail_provider_id.dart';
import '../../domain/usecases/load_settings.dart';
import '../../domain/usecases/update_settings.dart';
import '../../services/storage_folder/storage_folder_picker.dart';
import 'first_run_state.dart';

class FirstRunCubit extends Cubit<FirstRunState> {
  FirstRunCubit({
    required this._loadSettings,
    required this._updateSettings,
    required this._folderPicker,
    required this._logger,
  }) : super(const FirstRunState(language: AppLanguage.en));

  final LoadSettings _loadSettings;
  final UpdateSettings _updateSettings;
  final StorageFolderPicker _folderPicker;
  final AppLogger _logger;

  /// Preloads answers from an interrupted earlier run, if any.
  Future<void> start() async {
    final settings = await _loadSettings();
    if (isClosed) return;
    emit(FirstRunState.fromSettings(settings));
  }

  /// Language is persisted immediately so the UI switches while the wizard
  /// is still open.
  Future<void> selectLanguage(AppLanguage language) async {
    emit(state.copyWith(language: language));
    await _updateSettings((current) => current.copyWith(language: language));
  }

  Future<void> pickFolder() async {
    if (state.folderStatus == FolderPickStatus.picking) return;
    emit(state.copyWith(folderStatus: FolderPickStatus.picking));
    try {
      final folder = await _folderPicker.pickFolder();
      if (isClosed) return;
      if (folder == null) {
        emit(state.copyWith(folderStatus: FolderPickStatus.idle));
        return;
      }
      emit(state.copyWith(folder: folder, folderStatus: FolderPickStatus.idle));
    } catch (error, stackTrace) {
      _logger.error('Storage folder selection failed', error, stackTrace);
      if (isClosed) return;
      emit(state.copyWith(folderStatus: FolderPickStatus.failed));
    }
  }

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

  void setSaveToGallery(bool value) {
    emit(state.copyWith(saveToGallery: value));
  }

  void back() {
    final index = state.step.index;
    if (index == 0) return;
    emit(
      state.copyWith(step: FirstRunStep.values[index - 1], showErrors: false),
    );
  }

  Future<void> next() async {
    final snapshot = state;
    if (snapshot.completed) return;

    if (snapshot.errorsFor(snapshot.step).isNotEmpty) {
      emit(snapshot.copyWith(showErrors: true));
      return;
    }

    await _persist(snapshot);
    if (isClosed) return;

    if (snapshot.step == FirstRunStep.gallery) {
      emit(state.copyWith(completed: true, showErrors: false));
      return;
    }
    emit(
      state.copyWith(
        step: FirstRunStep.values[snapshot.step.index + 1],
        showErrors: false,
      ),
    );
  }

  Future<void> _persist(FirstRunState snapshot) async {
    switch (snapshot.step) {
      case FirstRunStep.welcome:
        // Language was already persisted by selectLanguage.
        break;
      case FirstRunStep.folder:
        await _updateSettings(
          (current) => current.copyWith(storageFolder: snapshot.folder),
        );
      case FirstRunStep.mail:
        await _updateSettings(
          (current) => current.copyWith(
            mailProvider: snapshot.provider,
            senderAccount: snapshot.senderAccount.trim(),
            destinationMode: snapshot.destinationMode,
            customDestination:
                snapshot.destinationMode == DestinationMode.custom
                ? snapshot.customDestination.trim()
                : null,
          ),
        );
      case FirstRunStep.gallery:
        await _updateSettings(
          (current) => current.copyWith(
            saveToGallery: snapshot.saveToGallery,
            firstRunCompleted: true,
          ),
        );
    }
  }
}
