import 'package:get_it/get_it.dart';
import 'package:one_click_scan/app/injection.dart';
import 'package:one_click_scan/core/config/app_config.dart';
import 'package:one_click_scan/core/logging/app_logger.dart';
import 'package:one_click_scan/data/datasources/key_value_store.dart';
import 'package:one_click_scan/domain/entities/storage_folder.dart';
import 'package:one_click_scan/services/ocr/ocr_services.dart';
import 'package:one_click_scan/services/mail/mail_services.dart';
import 'package:one_click_scan/services/pdf/pdf_services.dart';
import 'package:one_click_scan/services/camera/camera_service.dart';
import 'package:one_click_scan/domain/ports/gallery_service.dart';
import 'package:one_click_scan/domain/ports/scan_file_store.dart';
import 'package:one_click_scan/services/scan_files/scan_temp_store.dart';
import 'package:one_click_scan/services/storage_folder/storage_folder_picker.dart';

import 'scan_fakes.dart';

/// English by default so widget tests can assert on English strings.
const testConfig = AppConfig(
  appName: 'One Click Scan (test)',
  settingsSchemaVersion: 1,
  defaultLanguageCode: 'en',
);

/// Synthetic folder. Never use real user paths or names in tests.
const testFolder = StorageFolder(
  uri: 'content://com.example.test/tree/primary%3AScans',
  name: 'Scans',
);

class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, Object> data = <String, Object>{};

  @override
  String? getString(String key) => data[key] as String?;

  @override
  bool? getBool(String key) => data[key] as bool?;

  @override
  int? getInt(String key) => data[key] as int?;

  @override
  Future<void> setString(String key, String value) async => data[key] = value;

  @override
  Future<void> setBool(String key, bool value) async => data[key] = value;

  @override
  Future<void> setInt(String key, int value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);
}

class FakeStorageFolderPicker implements StorageFolderPicker {
  FakeStorageFolderPicker({this.result = testFolder, this.error});

  /// Returned by [pickFolder]; `null` simulates the user cancelling.
  StorageFolder? result;

  /// Thrown by [pickFolder] when set.
  Object? error;

  int pickCalls = 0;
  bool accessGranted = true;

  @override
  Future<StorageFolder?> pickFolder() async {
    pickCalls++;
    final failure = error;
    if (failure != null) throw failure;
    return result;
  }

  @override
  Future<bool> hasAccess(StorageFolder folder) async => accessGranted;
}

class RecordingLogger implements AppLogger {
  final List<String> messages = <String>[];

  @override
  void debug(String message) => messages.add(message);

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    messages.add(message);
  }
}

Future<GetIt> buildTestContainer({
  KeyValueStore? store,
  StorageFolderPicker? picker,
  AppLogger? logger,
  CameraService? camera,
  ScanFileStore? scanFileStore,
  GalleryService? gallery,
  ScanTempStore? scanTempStore,
  OcrServices? ocr,
  PdfServices? pdf,
  MailServices? mail,
  AppConfig? config,
  DateTime Function()? clock,
}) {
  return buildContainer(
    config: config ?? testConfig,
    keyValueStore: store ?? InMemoryKeyValueStore(),
    folderPicker: picker ?? FakeStorageFolderPicker(),
    logger: logger ?? RecordingLogger(),
    camera: camera ?? FakeCameraService(),
    scanFileStore: scanFileStore ?? FakeScanFileStore(),
    gallery: gallery ?? FakeGalleryService(),
    scanTempStore: scanTempStore ?? FakeScanTempStore(),
    ocr: ocr ?? const OcrServices.unsupported(),
    pdf: pdf ?? const PdfServices.unsupported(),
    mail: mail ?? const MailServices.unsupported(),
    clock: clock ?? () => DateTime(2026, 10, 21, 19, 5, 12),
  );
}
