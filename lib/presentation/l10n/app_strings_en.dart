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
      'When enabled, photos of your documents appear in the phone Gallery. '
      'Other apps with photo access can see them there, and they may be '
      'copied to cloud services if automatic backup is on (for example '
      'Google Photos). Leave it off if your documents contain sensitive '
      'data.';

  @override
  String get homeScanAndSend => 'SCAN & SEND';

  @override
  String get homeComingSoon => 'The camera arrives in the next phase.';

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
