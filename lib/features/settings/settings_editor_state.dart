import 'package:equatable/equatable.dart';

import '../../domain/entities/app_settings.dart';
import '../../domain/entities/destination_mode.dart';
import '../../domain/entities/mail_provider_id.dart';
import '../../domain/validation/mail_settings_validation.dart';

enum SettingsFolderStatus { idle, picking, failed }

const Object _unset = Object();

/// Language, folder and Gallery are saved immediately and live in [saved].
/// The e-mail section is an editable draft that is saved explicitly.
class SettingsEditorState extends Equatable {
  const SettingsEditorState({
    this.saved,
    this.provider,
    this.senderAccount = '',
    this.destinationMode = DestinationMode.own,
    this.customDestination = '',
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
  /// without typing does not count as a change.
  bool get hasChanges {
    final current = saved;
    if (current == null) return false;
    return provider != current.mailProvider ||
        senderAccount.trim() != (current.senderAccount ?? '') ||
        destinationMode != current.destinationMode ||
        normalizedCustomDestination != current.customDestination;
  }

  bool get canSave => hasChanges && errors.isEmpty;

  SettingsEditorState copyWith({
    AppSettings? saved,
    Object? provider = _unset,
    String? senderAccount,
    DestinationMode? destinationMode,
    String? customDestination,
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
      folderStatus: folderStatus ?? this.folderStatus,
      folderAccessLost: folderAccessLost ?? this.folderAccessLost,
      justSaved: justSaved ?? false,
    );
  }

  @override
  List<Object?> get props => [
    saved,
    provider,
    senderAccount,
    destinationMode,
    customDestination,
    folderStatus,
    folderAccessLost,
    justSaved,
  ];
}
