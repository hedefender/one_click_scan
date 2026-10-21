import 'dart:io' show Platform;

import 'android_storage_folder_picker.dart';
import 'storage_folder_picker.dart';
import 'unsupported_storage_folder_picker.dart';

StorageFolderPicker createPlatformStorageFolderPicker() {
  if (Platform.isAndroid) return AndroidStorageFolderPicker();
  return const UnsupportedStorageFolderPicker();
}
