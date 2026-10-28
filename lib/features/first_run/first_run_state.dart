import 'package:equatable/equatable.dart';

import '../../domain/entities/app_language.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/destination_mode.dart';
import '../../domain/entities/mail_provider_id.dart';
import '../../domain/entities/scan_flow_mode.dart';
import '../../domain/entities/storage_folder.dart';
import '../../domain/validation/mail_settings_validation.dart';

enum FirstRunStep { welcome, folder, mail, gallery, flow }

enum FirstRunError {
  folderMissing,
  providerMissing,
  senderInvalid,
  customDestinationInvalid,
  flowMissing,
}

enum FolderPickStatus { idle, picking, failed }

FirstRunError _fromMailError(MailSettingsError error) {
  return switch (error) {
    MailSettingsError.providerMissing => FirstRunError.providerMissing,
    MailSettingsError.senderInvalid => FirstRunError.senderInvalid,
    MailSettingsError.customDestinationInvalid =>
      FirstRunError.customDestinationInvalid,
  };
}

class FirstRunState extends Equatable {
  const FirstRunState({
    required this.language,
    this.step = FirstRunStep.welcome,
    this.folder,
    this.provider,
    this.senderAccount = '',
    this.destinationMode = DestinationMode.own,
    this.customDestination = '',
    this.saveToGallery = false,
    this.flowMode,
    this.showErrors = false,
    this.folderStatus = FolderPickStatus.idle,
    this.completed = false,
  });

  factory FirstRunState.fromSettings(AppSettings settings) {
    return FirstRunState(
      language: settings.language,
      folder: settings.storageFolder,
      provider: settings.mailProvider,
      senderAccount: settings.senderAccount ?? '',
      destinationMode: settings.destinationMode,
      customDestination: settings.customDestination ?? '',
      saveToGallery: settings.saveToGallery,
      flowMode: settings.scanFlowMode,
    );
  }

  final AppLanguage language;
  final FirstRunStep step;
  final StorageFolder? folder;
  final MailProviderId? provider;
  final String senderAccount;
  final DestinationMode destinationMode;
  final String customDestination;
  final bool saveToGallery;

  /// No default: null until the user picks one of the two (ADR-025).
  final ScanFlowMode? flowMode;

  /// Validation messages are only shown after the user tried to continue.
  final bool showErrors;
  final FolderPickStatus folderStatus;
  final bool completed;

  /// Validation rules for [forStep]. Empty set means the step can be left.
  Set<FirstRunError> errorsFor(FirstRunStep forStep) {
    switch (forStep) {
      case FirstRunStep.welcome:
      case FirstRunStep.gallery:
        return const <FirstRunError>{};
      case FirstRunStep.flow:
        return flowMode == null
            ? const <FirstRunError>{FirstRunError.flowMissing}
            : const <FirstRunError>{};
      case FirstRunStep.folder:
        return folder == null
            ? const <FirstRunError>{FirstRunError.folderMissing}
            : const <FirstRunError>{};
      case FirstRunStep.mail:
        return validateMailSettings(
          provider: provider,
          senderAccount: senderAccount,
          destinationMode: destinationMode,
          customDestination: customDestination,
        ).map(_fromMailError).toSet();
    }
  }

  FirstRunState copyWith({
    AppLanguage? language,
    FirstRunStep? step,
    StorageFolder? folder,
    MailProviderId? provider,
    String? senderAccount,
    DestinationMode? destinationMode,
    String? customDestination,
    bool? saveToGallery,
    ScanFlowMode? flowMode,
    bool? showErrors,
    FolderPickStatus? folderStatus,
    bool? completed,
  }) {
    return FirstRunState(
      language: language ?? this.language,
      step: step ?? this.step,
      folder: folder ?? this.folder,
      provider: provider ?? this.provider,
      senderAccount: senderAccount ?? this.senderAccount,
      destinationMode: destinationMode ?? this.destinationMode,
      customDestination: customDestination ?? this.customDestination,
      saveToGallery: saveToGallery ?? this.saveToGallery,
      flowMode: flowMode ?? this.flowMode,
      showErrors: showErrors ?? this.showErrors,
      folderStatus: folderStatus ?? this.folderStatus,
      completed: completed ?? this.completed,
    );
  }

  @override
  List<Object?> get props => [
    language,
    step,
    folder,
    provider,
    senderAccount,
    destinationMode,
    customDestination,
    saveToGallery,
    flowMode,
    showErrors,
    folderStatus,
    completed,
  ];
}
