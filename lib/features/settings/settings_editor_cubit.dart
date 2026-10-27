import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/entities/app_language.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/destination_mode.dart';
import '../../domain/entities/mail_provider_id.dart';
import '../../domain/entities/mail_send_mode.dart';
import '../../domain/mail/mail_outcome.dart';
import '../../domain/ports/mail_credential_store.dart';
import '../../domain/usecases/send_scan_pdf.dart';
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
    required this._credentials,
    required this._checkConnection,
    required this._openGuide,
    required this._logger,
  }) : super(const SettingsEditorState());

  final LoadSettings _loadSettings;
  final UpdateSettings _updateSettings;
  final StorageFolderPicker _folderPicker;
  final MailCredentialStore _credentials;
  final CheckMailConnection _checkConnection;
  final OpenProviderGuide _openGuide;
  final AppLogger _logger;

  Future<void> start() async {
    final settings = await _loadSettings();
    if (isClosed) return;
    emit(_draftFrom(settings, folderStatus: state.folderStatus));
    await _refreshStoredPassword(settings);
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

  /// How a scan leaves by e-mail. Saved at once, like the language.
  Future<void> selectSendMode(MailSendMode mode) {
    return _applyImmediately((current) => current.copyWith(mailSendMode: mode));
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
    emit(state.copyWith(provider: provider, mailTest: MailTestStatus.idle));
  }

  void setSenderAccount(String value) {
    emit(state.copyWith(senderAccount: value, mailTest: MailTestStatus.idle));
  }

  void setPassword(String value) {
    emit(state.copyWith(password: value, mailTest: MailTestStatus.idle));
  }

  void togglePasswordVisible() {
    emit(state.copyWith(passwordVisible: !state.passwordVisible));
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
    var stored = state.hasStoredPassword;
    final typed = snapshot.password;
    if (typed.isNotEmpty && snapshot.provider != null) {
      try {
        await _credentials.write(
          StoredMailSecret(
            provider: snapshot.provider!,
            accountEmail: snapshot.senderAccount.trim(),
            secret: typed,
          ),
        );
        stored = true;
      } catch (error, stackTrace) {
        // The kind of the error only: the password is never logged.
        _logger.error(
          'Storing the mail password failed',
          error.runtimeType,
          stackTrace,
        );
        stored = false;
      }
    } else if (stored) {
      // A password belongs to one provider and account: another one is none.
      stored = await _storedPasswordMatches(updated);
    }
    if (isClosed) return;
    emit(
      state.copyWith(
        saved: updated,
        justSaved: true,
        password: '',
        hasStoredPassword: stored,
      ),
    );
  }

  /// Signs in to the SMTP server with what is on the screen (the typed
  /// password, or the stored one) and sends nothing.
  Future<void> testConnection() async {
    if (state.mailTest == MailTestStatus.running) return;
    final provider = state.provider;
    final account = state.senderAccount.trim();
    var secret = state.password;
    if (secret.isEmpty && provider != null) {
      final stored = await _readStored();
      if (stored != null && stored.belongsTo(provider, account)) {
        secret = stored.secret;
      }
    }
    if (isClosed) return;
    if (secret.isEmpty) {
      emit(state.copyWith(mailTest: MailTestStatus.needsPassword));
      return;
    }
    emit(state.copyWith(mailTest: MailTestStatus.running));
    final MailOutcome outcome;
    try {
      outcome = await _checkConnection(
        provider: provider,
        accountEmail: account,
        secret: secret,
      );
    } catch (error, stackTrace) {
      _logger.error('The connection test threw', error.runtimeType, stackTrace);
      if (!isClosed) emit(state.copyWith(mailTest: MailTestStatus.unknown));
      return;
    }
    if (isClosed) return;
    // The diagnostic line: the step and the reply code, nothing else.
    final stage = outcome.stage;
    final code = outcome.replyCode ?? 0;
    emit(switch (outcome) {
      MailSent() => state.copyWith(mailTest: MailTestStatus.ok),
      MailAuthFailed() => state.copyWith(
        mailTest: MailTestStatus.authFailed,
        mailTestStage: stage,
        mailTestCode: code,
      ),
      MailNetworkError() => state.copyWith(
        mailTest: MailTestStatus.network,
        mailTestStage: stage,
        mailTestCode: code,
      ),
      MailRejected() => state.copyWith(
        mailTest: MailTestStatus.rejected,
        mailTestStage: stage,
        mailTestCode: code,
      ),
      _ => state.copyWith(mailTest: MailTestStatus.unknown),
    });
  }

  /// Opens the official page where the provider on the screen makes an app
  /// password, in the browser. Only for a link of the registry.
  Future<void> openGuide() async {
    final provider = state.provider;
    if (provider == null) return;
    final opened = await _openGuide(provider);
    if (isClosed) return;
    if (!opened) emit(state.copyWith(guideFailed: true));
  }

  /// Deletes the stored password (and what is typed).
  Future<void> deletePassword() async {
    try {
      await _credentials.delete();
    } catch (_) {
      if (!isClosed) {
        emit(state.copyWith(passwordNotice: MailPasswordNotice.deleteFailed));
      }
      return;
    }
    if (isClosed) return;
    emit(
      state.copyWith(
        password: '',
        hasStoredPassword: false,
        mailTest: MailTestStatus.idle,
        passwordNotice: MailPasswordNotice.deleted,
      ),
    );
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
        hasStoredPassword: state.hasStoredPassword,
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

  Future<StoredMailSecret?> _readStored() async {
    try {
      return await _credentials.read();
    } catch (error) {
      _logger.error('Reading the mail password failed', error.runtimeType);
      return null;
    }
  }

  Future<bool> _storedPasswordMatches(AppSettings settings) async {
    final stored = await _readStored();
    final provider = settings.mailProvider;
    return stored != null &&
        provider != null &&
        stored.belongsTo(provider, settings.senderAccount);
  }

  Future<void> _refreshStoredPassword(AppSettings settings) async {
    final matches = await _storedPasswordMatches(settings);
    if (isClosed) return;
    emit(state.copyWith(hasStoredPassword: matches));
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
    bool hasStoredPassword = false,
  }) {
    return SettingsEditorState(
      saved: settings,
      provider: settings.mailProvider,
      senderAccount: settings.senderAccount ?? '',
      destinationMode: settings.destinationMode,
      customDestination: settings.customDestination ?? '',
      hasStoredPassword: hasStoredPassword,
      folderStatus: folderStatus,
      folderAccessLost: folderAccessLost,
    );
  }
}
