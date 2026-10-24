import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app_strings_el.dart';
import 'app_strings_en.dart';

/// Hand-written localization (EL/EN). Adding a getter here forces both
/// languages to implement it, so translations can never silently go missing.
/// Can be migrated to ARB/gen_l10n later without touching call sites much.
abstract class AppStrings {
  const AppStrings();

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppStringsDelegate();

  static const supportedLocales = <Locale>[Locale('el'), Locale('en')];

  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings)!;
  }

  String get appTitle;

  // Wizard chrome
  String wizardStepIndicator(int current, int total);
  String get actionNext;
  String get actionBack;
  String get actionFinish;

  // Step 1: welcome + language
  String get welcomeTitle;
  String get welcomeBody;
  String get languageLabel;

  // Step 2: storage folder
  String get folderTitle;
  String get folderBody;
  String get folderPick;
  String get folderChange;
  String folderSelected(String name);
  String get folderRequired;
  String get folderPickFailed;

  // Step 3: mail
  String get mailTitle;
  String get mailBody;
  String get providerLabel;
  String get providerRequired;
  String get senderLabel;
  String get destinationLabel;
  String get destinationOwn;
  String get destinationCustom;
  String get customDestinationLabel;
  String get invalidEmail;

  // Step 4: gallery
  String get galleryTitle;
  String get galleryToggle;
  String get galleryNote;

  // Home
  String get homeScanAndSend;
  String get homeFolderLabel;
  String get homeRecipientLabel;
  String get homeProviderLabel;
  String get homeNotSet;
  String get homeFolderLostBanner;
  String get homeOpenSettings;

  // Scan
  String get scanModeSingle;
  String get scanModeMulti;
  String get scanCaptureButton;
  String get scanDone;
  String get scanDeleteLast;
  String scanPageCount(int count);
  String get scanSaving;
  String get scanRetry;
  String get scanPermissionDenied;
  String get scanOpenAppSettings;
  String get scanCameraUnavailable;
  String get scanCaptureFailed;
  String get scanSaveFailed;
  String get scanDiscardTitle;
  String get scanDiscardBody;
  String get scanResultTitle;
  String scanResultSummary(int count, String folderName);
  String get scanGallerySaved;
  String get scanGalleryFailed;
  String get scanBackHome;

  // Settings
  String get settingsTitle;
  String get settingsSaveButton;
  String get settingsSaved;
  String get settingsFolderAccessLost;
  String get settingsUnsavedTitle;
  String get settingsUnsavedBody;
  String get settingsDiscard;
  String get settingsStay;

  // OCR (check screen and settings)
  String get ocrOpenResult;
  String get ocrResultTitle;
  String ocrPageOf(int page, int total);
  String get ocrStatusQueued;
  String get ocrStatusLoadingModels;
  String get ocrStatusPreparing;
  String get ocrStatusDetecting;
  String ocrStatusRecognizing(int done, int total);
  String ocrSummaryPack(String name);
  String ocrSummaryDuration(String seconds);
  String ocrSummaryWorkImage(int width, int height);
  String ocrSummaryCapture(int width, int height, String megapixels);
  String ocrSummaryBoxes(int boxes, int filtered);
  String ocrSummaryBorderline(int count);
  String get ocrFilteredLabel;
  String get ocrNoText;
  String get ocrCopy;
  String get ocrCopied;
  String get ocrShowBoxes;
  String get ocrTimedOut;
  String get ocrCancelled;
  String get ocrFailedModel;
  String get ocrFailedImage;
  String get ocrFailedTooLarge;
  String get ocrFailedUnsupported;
  String get ocrFailedEngine;
  String get ocrSettingsTitle;
  String get ocrSettingsNote;
  String ocrPackName(String packId);
  String ocrPackDescription(String packId);
  String get licensesOpen;
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppStrings.supportedLocales.any(
      (supported) => supported.languageCode == locale.languageCode,
    );
  }

  @override
  Future<AppStrings> load(Locale locale) {
    final AppStrings strings = locale.languageCode == 'el'
        ? const AppStringsEl()
        : const AppStringsEn();
    return SynchronousFuture<AppStrings>(strings);
  }

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}
