import '../../domain/entities/mail_provider_id.dart';
import '../../domain/mail/mail_outcome.dart';
import 'app_strings.dart';

class AppStringsEn extends AppStrings {
  const AppStringsEn();

  @override
  String get appTitle => 'One Click Scan';

  @override
  String wizardStepIndicator(int current, int total) =>
      'Step $current of $total';

  @override
  String get actionNext => 'Next';

  @override
  String get actionBack => 'Back';

  @override
  String get actionFinish => 'Finish';

  @override
  String get welcomeTitle => 'Welcome';

  @override
  String get welcomeBody =>
      'Scan documents and send them with one tap. Everything runs locally '
      'on your phone. There is no account and no app cloud.';

  @override
  String get languageLabel => 'App language';

  @override
  String get folderTitle => 'Storage folder';

  @override
  String get folderBody =>
      'Choose a folder where your documents will be stored. This gives you '
      'direct access to your files and makes it easy to share them with '
      'other apps or with your own cloud storage.';

  @override
  String get folderPick => 'Choose folder';

  @override
  String get folderChange => 'Change folder';

  @override
  String folderSelected(String name) => 'Selected folder: $name';

  @override
  String get folderRequired => 'Choose a folder to continue.';

  @override
  String get folderPickFailed => 'The folder could not be selected. Try again.';

  @override
  String get mailTitle => 'Email delivery';

  @override
  String get mailBody =>
      'Documents are sent directly from the app. You can use an account '
      'different from the one on your device, so your main Sent folder '
      'does not fill up.';

  @override
  String get providerLabel => 'Email provider';

  @override
  String get providerRequired => 'Choose a provider.';

  @override
  String get senderLabel => 'Sending account (email)';

  @override
  String get destinationLabel => 'Recipient';

  @override
  String get destinationOwn => 'To my own email';

  @override
  String get destinationCustom => 'To another email';

  @override
  String get customDestinationLabel => 'Recipient email';

  @override
  String get invalidEmail => 'Invalid email address.';

  @override
  String get galleryTitle => 'Copies in Gallery';

  @override
  String get galleryToggle => 'Save originals to Gallery';

  @override
  String get galleryNote =>
      'When on, a copy of your photos appears in the phone Gallery. Other '
      'apps with access to photos can see it there, and it may be copied to '
      'cloud services if automatic backup is on (for example Google Photos). '
      'When off, the photos stay only in the folder you chose and do not '
      'appear in the Gallery. Leave it off if your documents contain '
      'sensitive data.';

  @override
  String get homeScanAndSend => 'SCAN & SEND';

  @override
  String get scanModeSingle => 'Single page';

  @override
  String get scanModeMulti => 'Multi page';

  @override
  String get scanCaptureButton => 'Take photo';

  @override
  String get scanDone => 'Done';

  @override
  String get scanDeleteLast => 'Delete last page';

  @override
  String scanPageCount(int count) => 'Pages: $count';

  @override
  String get scanSaving => 'Saving...';

  @override
  String get scanRetry => 'Try again';

  @override
  String get scanPermissionDenied =>
      'Camera access is needed to scan documents. Allow it to continue.';

  @override
  String get scanOpenAppSettings => 'App settings';

  @override
  String get scanCameraUnavailable =>
      'The camera is not available on this device.';

  @override
  String get scanCaptureFailed => 'The photo could not be taken. Try again.';

  @override
  String get scanSaveFailed =>
      'The pages could not be saved to your folder. They are kept, so you can '
      'try again.';

  @override
  String get scanDiscardTitle => 'Discard this scan?';

  @override
  String get scanDiscardBody => 'The pages you have taken will be deleted.';

  @override
  String get scanResultTitle => 'Scan saved';

  @override
  String scanResultSummary(int count, String folderName) => count == 1
      ? '1 file saved in "$folderName/pictures"'
      : '$count files saved in "$folderName/pictures"';

  @override
  String get scanGallerySaved => 'Copy saved to Gallery';

  @override
  String get scanGalleryFailed => 'Gallery copy failed';

  @override
  String get scanBackHome => 'Back to home';

  @override
  String get homeFolderLabel => 'Folder';

  @override
  String get homeRecipientLabel => 'Recipient';

  @override
  String get homeProviderLabel => 'Provider';

  @override
  String get homeNotSet => 'Not set';

  @override
  String get homeFolderLostBanner => 'The folder is no longer accessible';

  @override
  String get homeOpenSettings => 'Settings';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSaveButton => 'Save';

  @override
  String get settingsSaved => 'Settings saved.';

  @override
  String get settingsFolderAccessLost =>
      'The app no longer has access to this folder. Choose a folder again.';

  @override
  String get settingsUnsavedTitle => 'Unsaved changes';

  @override
  String get settingsUnsavedBody =>
      'You have changes to your email settings that are not saved.';

  @override
  String get settingsDiscard => 'Discard';

  @override
  String get settingsStay => 'Stay';

  @override
  String get ocrOpenResult => 'OCR text (check)';

  @override
  String get ocrResultTitle => 'OCR text';

  @override
  String ocrPageOf(int page, int total) => 'Page $page of $total';

  @override
  String get ocrStatusQueued => 'Waiting for the previous page';

  @override
  String get ocrStatusLoadingModels => 'Loading the language models';

  @override
  String get ocrStatusPreparing => 'Preparing the image';

  @override
  String get ocrStatusDetecting => 'Looking for text';

  @override
  String ocrStatusRecognizing(int done, int total) =>
      total == 0 ? 'Reading text' : 'Reading line $done of $total';

  @override
  String ocrSummaryPack(String name) => 'Language pack: $name';

  @override
  String ocrSummaryDuration(String seconds) => 'Time: $seconds s';

  @override
  String ocrSummaryWorkImage(int width, int height) =>
      'Working image: $width x $height px';

  @override
  String ocrSummaryCapture(int width, int height, String megapixels) =>
      'Capture: $width x $height px ($megapixels MP)';

  @override
  String ocrSummaryBoxes(int boxes, int filtered) =>
      'Boxes: $boxes (filtered: $filtered)';

  @override
  String ocrSummaryBorderline(int count) =>
      'Borderline lines (0.50 to 0.65): $count';

  @override
  String get ocrFilteredLabel => 'filtered, low confidence';

  @override
  String get ocrNoText => 'No text was found on this page.';

  @override
  String get ocrCopy => 'Copy text';

  @override
  String get ocrCopied => 'Text copied.';

  @override
  String get ocrShowBoxes => 'Show boxes on the image';

  @override
  String get ocrTimedOut => 'Reading this page took too long and was stopped.';

  @override
  String get ocrCancelled => 'Reading was cancelled.';

  @override
  String get ocrFailedModel =>
      'The language model is missing or damaged. Reinstall the app.';

  @override
  String get ocrFailedImage => 'The picture could not be read.';

  @override
  String get ocrFailedTooLarge =>
      'The picture is too large to read (over 400 megapixels).';

  @override
  String get ocrFailedUnsupported => 'Text reading is not available here.';

  @override
  String get ocrFailedEngine => 'Reading this page failed.';

  @override
  String get ocrSettingsTitle => 'Text reading language (OCR)';

  @override
  String get ocrSettingsNote =>
      'Choose the pack that matches your documents. The app does not guess '
      'the language: a Greek page read with the Latin pack, or a French page '
      'read with the Greek pack, comes out wrong. Everything is read on this '
      'phone, nothing is sent anywhere.';

  @override
  String ocrPackName(String packId) => switch (packId) {
    'greek' => 'Greek + English',
    'latin' => 'Latin script',
    _ => packId,
  };

  @override
  String ocrPackDescription(String packId) => switch (packId) {
    'greek' => 'Greek and English text.',
    'latin' =>
      'English and languages with Latin letters and accents: German, French, '
          'Spanish, Italian, Portuguese and more. Does not read Greek.',
    _ => '',
  };

  @override
  String get licensesOpen => 'Open-source licences';

  @override
  String get pdfTitle => 'PDF';

  @override
  String pdfReading(int page, int total) =>
      total <= 1 ? 'Reading the text…' : 'Reading page $page of $total…';

  @override
  String get pdfCreating => 'Creating the PDF…';

  @override
  String pdfSaved(String fileName) => 'PDF saved: $fileName';

  @override
  String pdfDetails(int pages, String size) =>
      pages == 1 ? '1 page, $size' : '$pages pages, $size';

  @override
  String pdfPagesWithoutText(int count) => count == 1
      ? '1 page has no searchable text. Its picture is in the PDF.'
      : '$count pages have no searchable text. Their pictures are in the PDF.';

  @override
  String get pdfTextNote =>
      'The text behind the pictures is read automatically and can contain '
      'mistakes. Always check the document itself.';

  @override
  String get pdfOpen => 'Open PDF';

  @override
  String get pdfSkipText => 'Create the PDF without waiting for the text';

  @override
  String get pdfRetry => 'Try again';

  @override
  String get pdfWait => 'Please wait until the PDF is ready.';

  @override
  String get pdfOpenNoViewer => 'No app on this phone can open PDF files.';

  @override
  String get pdfOpenFailed => 'The PDF could not be opened.';

  @override
  String get pdfFailedImage =>
      'The PDF could not be made: a photo is unreadable or too large. Your '
      'photos are saved.';

  @override
  String get pdfFailedUnsupported =>
      'Making a PDF is not available on this device. Your photos are saved.';

  @override
  String get pdfFailedBuild =>
      'The PDF could not be made. Your photos are saved.';

  @override
  String get pdfFailedNoAccess =>
      'The PDF could not be saved: the app no longer has access to your '
      'folder. Your photos are saved. Choose the folder again in Settings.';

  @override
  String get pdfFailedWrite =>
      'The PDF could not be written to your folder (is the storage full?). '
      'Your photos are saved.';

  @override
  String get mailPasswordLabel => 'App password';

  @override
  String get mailPasswordShow => 'Show the password';

  @override
  String get mailPasswordHide => 'Hide the password';

  @override
  String get mailPasswordStored => 'A password is stored on this phone.';

  @override
  String get mailPasswordNone => 'No password is stored.';

  @override
  String get mailPasswordPrivacy =>
      'The password is stored encrypted on the phone (Android Keystore). It is '
      'not in backups and it is not written anywhere else.';

  @override
  String get mailPasswordDelete => 'Delete the stored password';

  @override
  String get mailPasswordDeleted => 'The password was deleted.';

  @override
  String get mailPasswordDeleteFailed => 'The password could not be deleted.';

  @override
  String get mailTest => 'Test the connection';

  @override
  String get mailTestRunning => 'Testing the connection…';

  @override
  String get mailTestOk =>
      'The server accepted the account. No message was sent.';

  @override
  String get mailTestNeedsPassword =>
      'Enter the app password first (or save it).';

  @override
  String get mailModeTitle => 'How to send';

  @override
  String get mailModeSend => 'Send from the app';

  @override
  String get mailModeShare => 'Open in the e-mail app';

  @override
  String get mailModeShareNote =>
      '"Open in the e-mail app" opens your e-mail app with the recipient, the '
      'subject and the PDF filled in, and you press send there. No app '
      'password is needed. The e-mail app uses the account it already has '
      'selected.';

  @override
  String get mailHelpTitle => 'How to make the app password';

  @override
  List<String> mailHelpSteps(MailProviderId provider) => switch (provider) {
    MailProviderId.gmail => const [
      'Make sure your Google Account has 2-Step Verification turned on.',
      'Tap "Open the provider page". It opens in the browser and may ask you '
          'to sign in.',
      'Follow the page to make an app password (if it asks for a name, write '
          'for example One Click Scan).',
      'Copy the password and paste it above, without spaces.',
    ],
    MailProviderId.outlook => const [],
    MailProviderId.yahoo => const [
      'Tap "Open the provider page". The Yahoo Account Security page opens in '
          'the browser.',
      'Under "External connections" tap "Create app password".',
      'Enter a name (for example One Click Scan) and tap "Generate password".',
      'Copy the password and paste it above, without spaces.',
    ],
  };

  @override
  String? mailHelpNote(MailProviderId provider) => switch (provider) {
    MailProviderId.gmail =>
      '2-Step Verification must be on. The option is missing for accounts '
          'with security keys only, for work or school accounts (the '
          'administrator may forbid it) and with Advanced Protection. Use the '
          'backup way to send then.',
    MailProviderId.outlook => null,
    MailProviderId.yahoo =>
      'To make one, Yahoo asks for a browser you have been signed in to Yahoo '
          'with for several days, not a private window. $mailYahooSizeNote',
  };

  @override
  String get mailOutlookWarning =>
      'Outlook does not yet accept sending from the app with an app password. '
      'It will be supported after OAuth is built. For now use the backup way '
      'to send (open in the e-mail app).';

  @override
  String get mailYahooSizeNote =>
      'Yahoo does not state a size limit officially. The app assumes a '
      'message up to 20 MB fits.';

  @override
  String get mailGuideWhat =>
      'An app password is a separate password that the provider makes for one '
      'app only. It is not the normal password of your account, and with '
      '2-step verification on, the normal password is not accepted.';

  @override
  String get mailGuideReminder =>
      'The password is shown only once: copy it at once and paste it without '
      'spaces. The page of the provider may differ from this description.';

  @override
  String get mailGuideOpenPage => 'Open the provider page';

  @override
  String get mailGuideOpenFailed =>
      'No browser opened. Open the security page of your account by hand.';

  @override
  String get mailGuideOpenSettings => 'App password guide';

  @override
  String get mailGuideOutlook =>
      'There are no app password steps for Outlook: it is not supported for '
      'sending. It will be supported after OAuth is built. For now use the '
      'backup way to send.';

  @override
  String get mailFallbackButton => 'Use the backup way to send';

  @override
  String get mailFallbackReasonAuth =>
      'The provider did not accept an app password for this account. The '
      'backup way opens your e-mail app with the message ready.';

  @override
  String get mailFallbackReasonOutlook =>
      'Outlook does not yet support sending with an app password. The backup '
      'way opens your e-mail app with the message ready.';

  @override
  String mailDiagnostic(MailStage stage, int? code) {
    final name = switch (stage) {
      MailStage.connection => 'connection',
      MailStage.tls => 'TLS',
      MailStage.authentication => 'authentication',
      MailStage.sending => 'sending',
    };
    return code == null ? 'Step: $name' : 'Step: $name, code $code';
  }

  @override
  String get mailSendTitle => 'E-mail';

  @override
  String mailSendTo(String destination) =>
      'The PDF will be sent to $destination.';

  @override
  String get mailSendButton => 'Send';

  @override
  String get mailShareButton => 'Open in the e-mail app';

  @override
  String get mailShareNote =>
      'Your e-mail app opens with the message and the PDF ready. It uses the '
      'account that the e-mail app already has selected. The message leaves '
      'when you press send there.';

  @override
  String get mailSending => 'Sending…';

  @override
  String get mailCancel => 'Cancel sending';

  @override
  String get mailSent => 'The message was sent from the e-mail server.';

  @override
  String get mailRetry => 'Try again';

  @override
  String get mailOpenApp => 'Open in the e-mail app';

  @override
  String get mailOpenSettings => 'Open settings';

  @override
  String get mailNotConfiguredAccount =>
      'No e-mail account is set up for sending. Set it up in Settings.';

  @override
  String get mailNotConfiguredPassword =>
      'No app password is stored for this account. Enter it in Settings.';

  @override
  String get mailFailedAuth =>
      'The server did not accept the account or the password. With MFA '
      '(2-step verification) on, an app password made at the provider is '
      'needed, not the normal password of the account. For some accounts '
      '(for example work or school accounts) the administrator does not allow '
      'app passwords.';

  @override
  String get mailFailedNetwork =>
      'Could not connect to the e-mail server. Check the internet and try '
      'again.';

  @override
  String get mailFailedTooLarge =>
      'The PDF is too big to send by e-mail through this provider. Open it in '
      'the e-mail app or share it another way.';

  @override
  String mailFailedRejected(int code) => code == 0
      ? 'The e-mail server rejected the message.'
      : 'The e-mail server rejected the message (code $code).';

  @override
  String get mailFailedUnknown =>
      'The message was not sent because of an unexpected error.';

  @override
  String get mailDraftOpened =>
      'The e-mail app opened, with the account it already has selected. Press '
      'send there to send the message.';

  @override
  String get mailDraftOpenedGeneric =>
      'No e-mail app was found, so the generic share menu opened. Choose an '
      'app to send the PDF.';

  @override
  String get mailDraftNoApp =>
      'No e-mail app that takes an attachment was found.';

  @override
  String get mailDraftFailed =>
      'The PDF could not be handed to the e-mail app.';
}
