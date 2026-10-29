import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../domain/entities/mail_provider_id.dart';
import '../../domain/mail/mail_outcome.dart';
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

  // PDF (result screen)
  String get pdfTitle;
  String pdfReading(int page, int total);
  String get pdfCreating;
  String pdfSaved(String fileName);
  String pdfDetails(int pages, String size);
  String pdfPagesWithoutText(int count);
  String get pdfTextNote;
  String get pdfOpen;
  String get pdfSkipText;
  String get pdfRetry;
  String get pdfWait;
  String get pdfOpenNoViewer;
  String get pdfOpenFailed;
  String get pdfFailedImage;
  String get pdfFailedUnsupported;
  String get pdfFailedBuild;
  String get pdfFailedNoAccess;
  String get pdfFailedWrite;

  // Mail: account section of Settings
  String get mailPasswordLabel;
  String get mailPasswordShow;
  String get mailPasswordHide;
  String get mailPasswordStored;
  String get mailPasswordNone;
  String get mailPasswordPrivacy;
  String get mailPasswordDelete;
  String get mailPasswordDeleted;
  String get mailPasswordDeleteFailed;
  String get mailTest;
  String get mailTestRunning;
  String get mailTestOk;
  String get mailTestNeedsPassword;
  String get mailModeTitle;
  String get mailModeSend;
  String get mailModeShare;
  String get mailModeShareNote;
  String get mailHelpTitle;
  List<String> mailHelpSteps(MailProviderId provider);
  String? mailHelpNote(MailProviderId provider);
  String get mailOutlookWarning;
  String get mailYahooSizeNote;
  String get mailGuideWhat;
  String get mailGuideReminder;
  String get mailGuideOpenPage;
  String get mailGuideOpenFailed;
  String get mailGuideOpenSettings;
  String get mailGuideOutlook;
  String get mailFallbackButton;
  String get mailFallbackReasonAuth;
  String get mailFallbackReasonOutlook;

  /// One short line for a failure: the step and the 3 digit reply code of the
  /// server when there is one. Never an address, a host or a server text.
  String mailDiagnostic(MailStage stage, int? code);

  // Mail: sending from the result screen
  String get mailSendTitle;
  String mailSendTo(String destination);
  String get mailSendButton;
  String get mailShareButton;
  String get mailShareNote;
  String get mailSending;
  String get mailCancel;
  String get mailSent;
  String get mailRetry;
  String get mailOpenApp;
  String get mailOpenSettings;
  String get mailNotConfiguredAccount;
  String get mailNotConfiguredPassword;
  String get mailFailedAuth;
  String get mailFailedNetwork;
  String get mailFailedTooLarge;
  String mailFailedRejected(int code);
  String get mailFailedUnknown;
  String get mailDraftOpened;
  String get mailDraftNoApp;
  String get mailDraftFailed;
  String get mailDraftOpenedGeneric;

  // Phase 5: One Click or preview, cancel, discard
  String get flowTitle;
  String get flowBody;
  String get flowOneClick;
  String get flowOneClickNote;
  String get flowPreview;
  String get flowPreviewNote;
  String get flowRequired;
  String get settingsFlowTitle;
  String get settingsOneClickToggle;
  String get settingsFlowNote;
  String get flowCancel;
  String get stopTitle;
  String get stopBodyWriting;
  String get stopBodyProcessing;
  String get stopBodySending;
  String get stopContinue;
  String get stopConfirm;
  String get scanSaveCancelledMulti;
  String get scanSaveCancelledSingle;
  String autoReturnCountdown(int seconds);
  String get flowSharing;
  String get flowCancelledReading;
  String get flowCancelledSending;
  String get flowNotSent;
  String get flowNotSentNote;
  String get previewTitle;
  String get previewHint;
  String get previewDiscard;
  String get discardConfirmTitle;
  String get discardConfirmBody;
  String get discardConfirmYes;
  String get discardConfirmNo;
  String get discardRunning;
  String get discardDone;

  /// What a discard left behind (only the non-empty parts are named).
  String discardPartial(int pictures, bool pdf, int gallery);
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
