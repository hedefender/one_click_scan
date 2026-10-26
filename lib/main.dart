import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/injection.dart';
import 'core/config/app_config.dart';
import 'data/datasources/shared_preferences_key_value_store.dart';
import 'core/logging/app_logger.dart';
import 'domain/ocr/ocr_language_pack_registry.dart';
import 'presentation/licenses/ocr_licenses.dart';
import 'services/mail/mail_services.dart';
import 'services/ocr/ocr_services.dart';
import 'services/pdf/pdf_services.dart';
import 'services/scan_services_factory.dart';
import 'services/storage_folder/storage_folder_picker_factory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerOcrLicenses();

  final preferences = await SharedPreferences.getInstance();
  final scanServices = await createPlatformScanServices();
  // Pages left in the cache by a scan that was killed half way.
  await scanServices.tempStore.purgeAll();
  final ocr = await createPlatformOcrServices(
    registry: OcrLanguagePackRegistry.standard,
    logger: const DebugAppLogger(),
  );
  // Working copies left by a run that was killed half way.
  await ocr.workStore.purgeAll();
  final pdf = await createPlatformPdfServices(logger: const DebugAppLogger());
  // PDFs left in the cache by a run that was killed half way.
  await pdf.builder.purgeAll();
  final mail = await createPlatformMailServices(logger: const DebugAppLogger());
  // Copies of a PDF left in the cache by a send that was killed half way.
  await mail.attachments.purgeAll();
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
    ocr: ocr,
    pdf: pdf,
    mail: mail,
  );

  runApp(OneClickScanApp(container: container));
}
