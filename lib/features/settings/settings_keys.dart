import 'package:flutter/widgets.dart';

/// Widget keys used by widget and integration tests.
abstract final class SettingsKeys {
  static const language = Key('settings.language');
  static const changeFolder = Key('settings.changeFolder');
  static const folderAccessWarning = Key('settings.folderAccessWarning');
  static const sender = Key('settings.sender');
  static const customDestination = Key('settings.customDestination');
  static const save = Key('settings.save');
  static const gallerySwitch = Key('settings.gallerySwitch');
  static const licenses = Key('settings.licenses');
  static const password = Key('settings.mail.password');
  static const passwordToggle = Key('settings.mail.passwordToggle');
  static const passwordStatus = Key('settings.mail.passwordStatus');
  static const passwordDelete = Key('settings.mail.passwordDelete');
  static const mailTest = Key('settings.mail.test');
  static const mailTestResult = Key('settings.mail.testResult');
  static const sendMode = Key('settings.mail.sendMode');
  static const help = Key('settings.mail.help');
  static const providerWarning = Key('settings.mail.providerWarning');
  static Key ocrPack(String id) => Key('settings.ocrPack.$id');
  static const dialogDiscard = Key('settings.dialog.discard');
  static const dialogStay = Key('settings.dialog.stay');
}
