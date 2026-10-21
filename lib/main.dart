import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/injection.dart';
import 'core/config/app_config.dart';
import 'data/datasources/shared_preferences_key_value_store.dart';
import 'services/scan_services_factory.dart';
import 'services/storage_folder/storage_folder_picker_factory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  final scanServices = await createPlatformScanServices();
  // Pages left in the cache by a scan that was killed half way.
  await scanServices.tempStore.purgeAll();
  final container = await buildContainer(
    config: AppConfig.forDeviceLanguage(
      PlatformDispatcher.instance.locale.languageCode,
    ),
    keyValueStore: SharedPreferencesKeyValueStore(preferences),
    folderPicker: createPlatformStorageFolderPicker(),
    camera: scanServices.camera,
    scanFileStore: scanServices.fileStore,
    gallery: scanServices.gallery,
    scanTempStore: scanServices.tempStore,
  );

  runApp(OneClickScanApp(container: container));
}
