import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/injection.dart';
import 'core/config/app_config.dart';
import 'data/datasources/shared_preferences_key_value_store.dart';
import 'services/storage_folder/storage_folder_picker_factory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  final container = await buildContainer(
    config: AppConfig.forDeviceLanguage(
      PlatformDispatcher.instance.locale.languageCode,
    ),
    keyValueStore: SharedPreferencesKeyValueStore(preferences),
    folderPicker: createPlatformStorageFolderPicker(),
  );

  runApp(OneClickScanApp(container: container));
}
