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
  static Key ocrPack(String id) => Key('settings.ocrPack.$id');
  static const dialogDiscard = Key('settings.dialog.discard');
  static const dialogStay = Key('settings.dialog.stay');
}
