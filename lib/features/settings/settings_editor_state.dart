import 'package:equatable/equatable.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/entities/destination_mode.dart';
import '../../domain/entities/mail_provider_id.dart';
import '../../domain/mail/mail_outcome.dart';
import '../../domain/validation/mail_settings_validation.dart';

enum SettingsFolderStatus { idle, picking, failed }

/// The state of the "Test the connection" button. The test signs in and sends
/// nothing.
enum MailTestStatus {
  idle,
  running,
  ok,
  needsPassword,
  authFailed,
  network,
  rejected,
  unknown,
}

/// What happened to the stored password last (drives a snackbar).
enum MailPasswordNotice { none, deleted, deleteFailed }

const Object _unset = Object();

/// Language, folder, Gallery and the way to send are saved immediately and live
/// in [saved]. The e-mail section is an editable draft that is saved
/// explicitly.
class SettingsEditorState extends Equatable {
  const SettingsEditorState({
    this.saved,
    this.provider,
    this.senderAccount = '',
    this.destinationMode = DestinationMode.own,
    this.customDestination = '',
    this.password = '',
    this.passwordVisible = false,
    this.hasStoredPassword = false,
    this.mailTest = MailTestStatus.idle,
    this.mailTestCode = 0,
    this.mailTestStage,
    this.guideFailed = false,
    this.passwordNotice = MailPasswordNotice.none,
    this.folderStatus = SettingsFolderStatus.idle,
    this.folderAccessLost = false,
    this.justSaved = false,
  });

  /// Last persisted settings. `null` until loaded.
  final AppSettings? saved;
  final MailProviderId? provider;
  final String senderAccount;
  final DestinationMode destinationMode;
  final String customDestination;

  /// What is typed in the password field. Lives only here and in the field,
  /// until Save writes it to secure storage; never logged.
  final String password;
  final bool passwordVisible;

  /// A password is stored for the saved provider and account.
  final bool hasStoredPassword;
  final MailTestStatus mailTest;

  /// The reply code of the server for a failed test, 0 when there is none.
  final int mailTestCode;

  /// The step that failed (the diagnostic line), null when there is none.
  final MailStage? mailTestStage;

  /// True only in the state after the guide page could not be opened.
  final bool guideFailed;
  final MailPasswordNotice passwordNotice;
  final SettingsFolderStatus folderStatus;

  /// The stored folder exists but the platform no longer grants access.
  final bool folderAccessLost;

  /// True only in the state emitted by a successful save (drives a snackbar).
  final bool justSaved;

  bool get isLoaded => saved != null;

  Set<MailSettingsError> get errors => validateMailSettings(
    provider: provider,
    senderAccount: senderAccount,
    destinationMode: destinationMode,
    customDestination: customDestination,
  );

  /// Same normalization the wizard uses when it persists the mail step.
  String? get normalizedCustomDestination =>
      destinationMode == DestinationMode.custom
      ? customDestination.trim()
      : null;

  /// Whether the draft differs from what is stored. Compared on the values
  /// that would be persisted, so toggling the recipient mode back and forth
  /// without typing does not count as a change. A typed password is a change.
  bool get hasChanges {
    final current = saved;
    if (current == null) return false;
    return provider != current.mailProvider ||
        senderAccount.trim() != (current.senderAccount ?? '') ||
        destinationMode != current.destinationMode ||
        normalizedCustomDestination != current.customDestination ||
        password.isNotEmpty;
  }

  bool get canSave => hasChanges && errors.isEmpty;

  SettingsEditorState copyWith({
    AppSettings? saved,
    Object? provider = _unset,
    String? senderAccount,
    DestinationMode? destinationMode,
    String? customDestination,
    String? password,
    bool? passwordVisible,
    bool? hasStoredPassword,
    MailTestStatus? mailTest,
    int? mailTestCode,
    MailStage? mailTestStage,
    bool? guideFailed,
    MailPasswordNotice? passwordNotice,
    SettingsFolderStatus? folderStatus,
    bool? folderAccessLost,
    bool? justSaved,
  }) {
    return SettingsEditorState(
      saved: saved ?? this.saved,
      provider: identical(provider, _unset)
          ? this.provider
          : provider as MailProviderId?,
      senderAccount: senderAccount ?? this.senderAccount,
      destinationMode: destinationMode ?? this.destinationMode,
      customDestination: customDestination ?? this.customDestination,
      password: password ?? this.password,
      passwordVisible: passwordVisible ?? this.passwordVisible,
      hasStoredPassword: hasStoredPassword ?? this.hasStoredPassword,
      mailTest: mailTest ?? this.mailTest,
      mailTestCode: mailTestCode ?? this.mailTestCode,
      mailTestStage: mailTestStage ?? this.mailTestStage,
      guideFailed: guideFailed ?? false,
      passwordNotice: passwordNotice ?? MailPasswordNotice.none,
      folderStatus: folderStatus ?? this.folderStatus,
      folderAccessLost: folderAccessLost ?? this.folderAccessLost,
      justSaved: justSaved ?? false,
    );
  }

  /// Never prints the typed password.
  @override
  String toString() => 'SettingsEditorState(<redacted>)';

  @override
  List<Object?> get props => [
    saved,
    provider,
    senderAccount,
    destinationMode,
    customDestination,
    password,
    passwordVisible,
    hasStoredPassword,
    mailTest,
    mailTestCode,
    mailTestStage,
    guideFailed,
    passwordNotice,
    folderStatus,
    folderAccessLost,
    justSaved,
  ];
}
