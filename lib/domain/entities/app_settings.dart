import 'package:equatable/equatable.dart';

import 'app_language.dart';
import 'destination_mode.dart';
import '../ocr/ocr_language_pack_registry.dart';
import 'mail_provider_id.dart';
import 'storage_folder.dart';

const Object _unset = Object();

class AppSettings extends Equatable {
  const AppSettings({
    required this.language,
    this.firstRunCompleted = false,
    this.storageFolder,
    this.mailProvider,
    this.senderAccount,
    this.destinationMode = DestinationMode.own,
    this.customDestination,
    this.saveToGallery = false,
    this.ocrPackId = OcrPackIds.latin,
  });

  final AppLanguage language;
  final bool firstRunCompleted;
  final StorageFolder? storageFolder;
  final MailProviderId? mailProvider;

  /// Account the app sends from. May differ from the account configured on
  /// the device, so the user's main "Sent" folder does not fill up.
  final String? senderAccount;
  final DestinationMode destinationMode;
  final String? customDestination;

  /// Copy original photos to the phone Gallery. Off by default (privacy).
  final bool saveToGallery;

  /// Id of the OCR language pack the user chose (`greek`, `latin`). The
  /// scanner never guesses the language: a Greek page read with the Latin
  /// pack, or the other way round, comes out wrong.
  final String ocrPackId;

  /// Address documents are delivered to, according to [destinationMode].
  String? get effectiveDestination {
    return switch (destinationMode) {
      DestinationMode.own => senderAccount,
      DestinationMode.custom => customDestination,
    };
  }

  /// Nullable fields use a sentinel so passing `null` explicitly clears them.
  AppSettings copyWith({
    AppLanguage? language,
    bool? firstRunCompleted,
    Object? storageFolder = _unset,
    Object? mailProvider = _unset,
    Object? senderAccount = _unset,
    DestinationMode? destinationMode,
    Object? customDestination = _unset,
    bool? saveToGallery,
    String? ocrPackId,
  }) {
    return AppSettings(
      language: language ?? this.language,
      firstRunCompleted: firstRunCompleted ?? this.firstRunCompleted,
      storageFolder: identical(storageFolder, _unset)
          ? this.storageFolder
          : storageFolder as StorageFolder?,
      mailProvider: identical(mailProvider, _unset)
          ? this.mailProvider
          : mailProvider as MailProviderId?,
      senderAccount: identical(senderAccount, _unset)
          ? this.senderAccount
          : senderAccount as String?,
      destinationMode: destinationMode ?? this.destinationMode,
      customDestination: identical(customDestination, _unset)
          ? this.customDestination
          : customDestination as String?,
      saveToGallery: saveToGallery ?? this.saveToGallery,
      ocrPackId: ocrPackId ?? this.ocrPackId,
    );
  }

  @override
  List<Object?> get props => [
    language,
    firstRunCompleted,
    storageFolder,
    mailProvider,
    senderAccount,
    destinationMode,
    customDestination,
    saveToGallery,
    ocrPackId,
  ];
}
