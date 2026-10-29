import 'package:get_it/get_it.dart';

import '../core/config/app_config.dart';
import '../core/logging/app_logger.dart';
import '../data/datasources/key_value_gallery_counter_store.dart';
import '../data/datasources/key_value_store.dart';
import '../data/datasources/settings_local_data_source.dart';
import '../data/repositories/settings_repository_impl.dart';
import '../domain/entities/app_language.dart';
import '../domain/repositories/settings_repository.dart';
import '../domain/ocr/ocr_language_pack_registry.dart';
import '../domain/ports/ocr_engine.dart';
import '../domain/ports/open_pdf.dart';
import '../domain/ports/pdf_builder.dart';
import '../domain/usecases/load_settings.dart';
import '../domain/usecases/store_scan_pdf.dart';
import '../services/pdf/pdf_services.dart';
import '../services/mail/mail_services.dart';
import '../domain/mail/mail_provider.dart';
import '../domain/ports/attachment_source.dart';
import '../domain/ports/draft_sharer.dart';
import '../domain/ports/link_opener.dart';
import '../domain/ports/mail_app_finder.dart';
import '../domain/ports/mail_credential_store.dart';
import '../domain/ports/mail_sender.dart';
import '../domain/usecases/discard_scan.dart';
import '../domain/usecases/scan_and_send.dart';
import '../domain/usecases/send_scan_pdf.dart';
import '../domain/usecases/prepare_image_for_ocr.dart';
import '../domain/usecases/recognize_pages.dart';
import '../services/ocr/ocr_services.dart';
import '../domain/scan/gallery_naming.dart';
import '../domain/scan/scan_naming.dart';
import '../domain/usecases/store_scan_pages.dart';
import '../domain/usecases/update_settings.dart';
import '../features/first_run/first_run_module.dart';
import '../features/home/home_module.dart';
import '../features/scan/scan_module.dart';
import '../features/settings/settings_module.dart';
import '../presentation/state/settings_cubit.dart';
import '../services/camera/camera_service.dart';
import '../services/camera/unsupported_camera_service.dart';
import '../domain/ports/gallery_service.dart';
import '../domain/ports/scan_file_store.dart';
import '../services/scan_files/scan_temp_store.dart';
import '../services/scan_files/unsupported_scan_file_store.dart';
import '../services/storage_folder/storage_folder_picker.dart';

/// Composition root.
///
/// Builds a fresh container each call (no global singleton), which keeps
/// tests isolated: platform adapters are passed in, so tests inject fakes.
Future<GetIt> buildContainer({
  required AppConfig config,
  required KeyValueStore keyValueStore,
  required StorageFolderPicker folderPicker,
  AppLogger logger = const DebugAppLogger(),
  CameraService camera = const UnsupportedCameraService(),
  ScanFileStore scanFileStore = const UnsupportedScanFileStore(),
  GalleryService gallery = const UnsupportedGalleryService(),
  ScanTempStore scanTempStore = const NoopScanTempStore(),
  OcrServices ocr = const OcrServices.unsupported(),
  PdfServices pdf = const PdfServices.unsupported(),
  MailServices mail = const MailServices.unsupported(),
  OcrLanguagePackRegistry? ocrPackRegistry,
  DateTime Function() clock = DateTime.now,
}) async {
  final sl = GetIt.asNewInstance();
  final packRegistry = ocrPackRegistry ?? OcrLanguagePackRegistry.standard;

  // Core and platform adapters.
  sl.registerSingleton<AppConfig>(config);
  sl.registerSingleton<AppLogger>(logger);
  sl.registerSingleton<KeyValueStore>(keyValueStore);
  sl.registerSingleton<StorageFolderPicker>(folderPicker);
  sl.registerSingleton<CameraService>(camera);
  sl.registerSingleton<ScanFileStore>(scanFileStore);
  sl.registerSingleton<GalleryService>(gallery);
  sl.registerSingleton<ScanTempStore>(scanTempStore);
  sl.registerSingleton<OcrLanguagePackRegistry>(packRegistry);
  sl.registerSingleton<OcrEngine>(ocr.engine);
  sl.registerSingleton<PdfBuilder>(pdf.builder);
  sl.registerSingleton<OpenPdf>(pdf.opener);
  sl.registerSingleton<MailSender>(mail.sender);
  sl.registerSingleton<MailCredentialStore>(mail.credentials);
  sl.registerSingleton<AttachmentSource>(mail.attachments);
  sl.registerSingleton<DraftSharer>(mail.sharer);
  sl.registerSingleton<MailAppFinder>(mail.appFinder);
  sl.registerSingleton<LinkOpener>(mail.links);
  sl.registerSingleton<MailProviderRegistry>(mail.providers);

  // Data.
  sl.registerLazySingleton<SettingsLocalDataSource>(
    () => SettingsLocalDataSource(
      store: sl<KeyValueStore>(),
      schemaVersion: sl<AppConfig>().settingsSchemaVersion,
      defaultLanguage:
          AppLanguage.fromCode(sl<AppConfig>().defaultLanguageCode) ??
          AppLanguage.en,
      packRegistry: packRegistry,
    ),
  );
  sl.registerLazySingleton<SettingsRepository>(
    () => SettingsRepositoryImpl(sl<SettingsLocalDataSource>()),
  );

  // Domain.
  sl.registerLazySingleton<LoadSettings>(
    () => LoadSettings(sl<SettingsRepository>()),
  );
  sl.registerLazySingleton<UpdateSettings>(
    () => UpdateSettings(sl<SettingsRepository>()),
  );

  sl.registerLazySingleton<StoreScanPages>(
    () => StoreScanPages(
      fileStore: sl<ScanFileStore>(),
      gallery: sl<GalleryService>(),
      naming: ScanNaming(clock),
      galleryNaming: GalleryNaming(clock),
      galleryCounter: KeyValueGalleryCounterStore(sl<KeyValueStore>()),
      logger: sl<AppLogger>(),
    ),
  );

  sl.registerLazySingleton<StoreScanPdf>(
    () => StoreScanPdf(
      builder: sl<PdfBuilder>(),
      fileStore: sl<ScanFileStore>(),
      naming: ScanNaming(clock),
      logger: sl<AppLogger>(),
    ),
  );

  sl.registerLazySingleton<SendScanPdf>(
    () => SendScanPdf(
      sender: sl<MailSender>(),
      attachments: sl<AttachmentSource>(),
      credentials: sl<MailCredentialStore>(),
      providers: sl<MailProviderRegistry>(),
      logger: sl<AppLogger>(),
    ),
  );
  sl.registerLazySingleton<ShareScanPdfDraft>(
    () => ShareScanPdfDraft(
      sharer: sl<DraftSharer>(),
      finder: sl<MailAppFinder>(),
      providers: sl<MailProviderRegistry>(),
    ),
  );
  sl.registerLazySingleton<ScanAndSend>(
    () => ScanAndSend(
      loadSettings: sl<LoadSettings>(),
      storePdf: sl<StoreScanPdf>(),
      send: sl<SendScanPdf>(),
      share: sl<ShareScanPdfDraft>(),
      fileStore: sl<ScanFileStore>(),
      logger: sl<AppLogger>(),
    ),
  );
  sl.registerLazySingleton<DiscardScan>(
    () => DiscardScan(
      fileStore: sl<ScanFileStore>(),
      gallery: sl<GalleryService>(),
      logger: sl<AppLogger>(),
    ),
  );
  sl.registerLazySingleton<OpenProviderGuide>(
    () => OpenProviderGuide(
      opener: sl<LinkOpener>(),
      providers: sl<MailProviderRegistry>(),
    ),
  );
  sl.registerLazySingleton<CheckMailConnection>(
    () => CheckMailConnection(
      sender: sl<MailSender>(),
      providers: sl<MailProviderRegistry>(),
    ),
  );

  sl.registerLazySingleton<RecognizePages>(
    () => RecognizePages(
      engine: sl<OcrEngine>(),
      workStore: ocr.workStore,
      prepare: PrepareImageForOcr(
        headerReader: ocr.headerReader,
        dartMaker: ocr.dartMaker,
        nativeMaker: ocr.nativeMaker,
        workStore: ocr.workStore,
      ),
    ),
  );

  // Feature modules.
  registerFirstRunModule(sl);
  registerHomeModule(sl);
  registerSettingsModule(sl);
  registerScanModule(sl);

  // App-wide state, created after settings can be read.
  final initialSettings = await sl<LoadSettings>()();
  sl.registerSingleton<SettingsCubit>(
    SettingsCubit(sl<SettingsRepository>(), initialSettings),
  );

  return sl;
}
