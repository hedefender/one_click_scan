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
}
