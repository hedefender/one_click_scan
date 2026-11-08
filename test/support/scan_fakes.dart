import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:one_click_scan/domain/lighting/flash_mode.dart';
import 'package:one_click_scan/domain/lighting/light_metric.dart';
import 'package:one_click_scan/domain/ports/light_meter.dart';
import 'package:one_click_scan/core/errors/app_exceptions.dart';
import 'package:one_click_scan/domain/entities/captured_page.dart';
import 'package:one_click_scan/domain/entities/storage_folder.dart';
import 'package:one_click_scan/services/camera/camera_service.dart';
import 'package:one_click_scan/domain/ports/gallery_service.dart';
import 'package:one_click_scan/domain/ports/scan_file_store.dart';
import 'package:one_click_scan/services/scan_files/scan_temp_store.dart';

/// No real camera. Shots are synthetic paths; nothing is read from a device.
class FakeCameraService implements CameraService {
  FakeCameraService({
    this.openResults = const [CameraOpenResult.ready],
    this.flashAvailable = false,
  });

  /// What [hasFlash] answers.
  bool flashAvailable;
  FlashMode _flash = FlashMode.off;
  final List<FlashMode> flashSet = <FlashMode>[];
  final List<Offset> focusPoints = <Offset>[];
  final _samples = StreamController<LightMetric>.broadcast();
  int analysisStarts = 0;
  int analysisStops = 0;

  /// Pushes a preview sample, as the analyser would.
  void emitSample(LightMetric metric) => _samples.add(metric);

  /// Results of successive [open] calls; the last one repeats.
  List<CameraOpenResult> openResults;

  /// When true, [capture] throws.
  bool failCapture = false;

  int openCalls = 0;
  int closeCalls = 0;
  int openSettingsCalls = 0;
  bool isOpen = false;
  final List<String> captured = <String>[];
  int _shots = 0;

  @override
  Future<CameraOpenResult> open() async {
    final index = openCalls < openResults.length
        ? openCalls
        : openResults.length - 1;
    openCalls++;
    final result = openResults[index];
    isOpen = result == CameraOpenResult.ready;
    // Like the plugin: a camera that is opened starts with the flash off.
    _flash = FlashMode.off;
    _torchLit = false;
    return result;
  }

  @override
  Widget buildPreview(BuildContext context) {
    return const SizedBox(width: 10, height: 10);
  }

  @override
  Future<CapturedPage> capture({required int order}) async {
    if (failCapture) throw const CameraCaptureException('fake failure');
    _shots++;
    final path = 'cache/fake_page_$_shots.jpg';
    captured.add(path);
    return CapturedPage(path: path, order: order);
  }

  @override
  Future<void> close() async {
    closeCalls++;
    isOpen = false;
    if (_torchLit) torchLog.add(false);
    _torchLit = false;
  }

  @override
  Future<void> openAppSettings() async => openSettingsCalls++;

  @override
  bool get hasFlash => flashAvailable;

  @override
  FlashMode get flashMode => _flash;

  @override
  Future<void> setFlashMode(FlashMode mode) async {
    _flash = mode;
    flashSet.add(mode);
    // Off and Auto put the torch out; On never lights it by itself.
    if (_torchLit) {
      _torchLit = false;
      torchLog.add(false);
    }
  }

  bool _torchLit = false;

  /// Every change of the torch, in order (true = lit, false = out).
  final List<bool> torchLog = <bool>[];

  /// How many times the torch was actually lit.
  int get torchLights => torchLog.where((lit) => lit).length;

  @override
  bool get torchLit => _torchLit;

  @override
  Future<void> setTorchLit(bool lit) async {
    if (!isOpen || _flash != FlashMode.on || lit == _torchLit) return;
    _torchLit = lit;
    torchLog.add(lit);
  }

  @override
  Future<void> focusAt(Offset point) async => focusPoints.add(point);

  @override
  Stream<LightMetric> get lightSamples => _samples.stream;

  @override
  void startLightAnalysis() => analysisStarts++;

  @override
  void stopLightAnalysis() => analysisStops++;
}

/// Light meter that answers by path (default: bright, so nothing is dark).
class FakeLightMeter implements LightMeter {
  FakeLightMeter();

  static const bright = LightMetric(paper: 90, contrast: 60);
  static const dark = LightMetric(paper: 20, contrast: 12);

  final Map<String, LightMetric?> byPath = {};
  LightMetric? fallback = bright;
  final List<String> measured = <String>[];

  @override
  Future<LightMetric?> measureFile(String path) async {
    measured.add(path);
    return byPath.containsKey(path) ? byPath[path] : fallback;
  }
}

/// In-memory stand-in for the user's folder (no SAF).
class FakeScanFileStore implements ScanFileStore {
  /// sub-folder name -> file names.
  final Map<String, List<String>> folders = <String, List<String>>{};

  /// Fail the Nth `copyToFolder` call (1-based) of the current attempt.
  int? failOnCopyNumber;
  ScanStoreFailure failure = ScanStoreFailure.writeFailed;

  /// Fail every call with this failure (for example `noAccess`).
  ScanStoreFailure? failEverything;

  int copyCalls = 0;
  final List<String> deleted = <String>[];

  List<String> files(String subfolder) => folders[subfolder] ?? <String>[];

  void _checkAll() {
    final all = failEverything;
    if (all != null) throw ScanStoreException(all);
  }

  @override
  Future<void> ensureSubfolder(StorageFolder folder, String name) async {
    _checkAll();
    calls.add('subfolder:$name');
    folders.putIfAbsent(name, () => <String>[]);
  }

  /// Sub-folders that got a `.nomedia` marker.
  final Set<String> noMedia = <String>{};

  /// Every `ensureNoMedia` call, in order (to check the call order).
  final List<String> calls = <String>[];

  /// Make `ensureNoMedia` fail (the scan must go on).
  bool failNoMedia = false;

  @override
  Future<void> ensureNoMedia(StorageFolder folder, String subfolder) async {
    _checkAll();
    calls.add('noMedia:$subfolder');
    if (failNoMedia) {
      throw const ScanStoreException(ScanStoreFailure.writeFailed);
    }
    noMedia.add(subfolder);
  }

  @override
  Future<List<String>> listFileNames(
    StorageFolder folder,
    String subfolder,
  ) async {
    _checkAll();
    return [...files(subfolder)];
  }

  /// Every copied file as (sub-folder, file name, source path), in order.
  final List<(String, String, String)> copies = <(String, String, String)>[];

  /// Fail the copies into this sub-folder only (for example `pdf`).
  String? failSubfolder;

  /// A file with this (sub-folder, name) shows up just before the first copy,
  /// after the listing (two scans racing for a name).
  (String, String)? raceOnFirstCopy;

  /// Called after each copy with the 1-based number of the copy (lets a test
  /// cancel in the middle of a save).
  void Function(int copyNumber)? onCopied;

  /// When set, every `copyToFolder` waits for it (a save that takes time).
  Completer<void>? copyGate;

  @override
  Future<String> copyToFolder({
    required StorageFolder folder,
    required String subfolder,
    required String fileName,
    required String mimeType,
    required String sourcePath,
  }) async {
    _checkAll();
    await copyGate?.future;
    calls.add('copy:$fileName');
    copyCalls++;
    if (failOnCopyNumber == copyCalls) throw ScanStoreException(failure);
    if (failSubfolder == subfolder) throw ScanStoreException(failure);
    final race = raceOnFirstCopy;
    if (race != null) {
      raceOnFirstCopy = null;
      folders.putIfAbsent(race.$1, () => <String>[]).add(race.$2);
    }
    final list = folders.putIfAbsent(subfolder, () => <String>[]);
    if (list.contains(fileName)) {
      throw const ScanStoreException(ScanStoreFailure.exists);
    }
    list.add(fileName);
    copies.add((subfolder, fileName, sourcePath));
    onCopied?.call(copyCalls);
    return 'content://com.example.test/tree/Scans/document/$subfolder%2F$fileName';
  }

  /// URIs deleted by [deleteByUri], in order.
  final List<String> deletedUris = <String>[];

  /// URIs whose deletion fails (a file that could not be deleted).
  final Set<String> failDeleteUris = <String>{};

  @override
  Future<void> deleteByUri(String uri) async {
    if (failDeleteUris.contains(uri)) {
      throw const ScanStoreException(ScanStoreFailure.writeFailed);
    }
    deletedUris.add(uri);
    // The fake URI ends with `<subfolder>%2F<fileName>`.
    final tail = uri.split('/document/').last;
    final parts = tail.split('%2F');
    if (parts.length == 2) files(parts[0]).remove(parts[1]);
  }

  @override
  Future<void> deleteFile({
    required StorageFolder folder,
    required String subfolder,
    required String fileName,
  }) async {
    deleted.add(fileName);
    files(subfolder).remove(fileName);
  }
}

class FakeGalleryService implements GalleryService {
  bool fail = false;
  final List<String> saved = <String>[];

  /// The file names handed to the Gallery, in the same order as [saved].
  final List<String> savedNames = <String>[];

  /// Called after each saved image (lets a test move the clock).
  void Function()? onSave;

  /// Gallery URIs deleted by [deleteImage], in order.
  final List<String> deletedUris = <String>[];

  /// Gallery URIs whose deletion fails.
  final Set<String> failDeleteUris = <String>{};

  @override
  Future<String> saveImage(String path, {required String fileName}) async {
    if (fail) throw const GalleryException('fake failure');
    saved.add(path);
    savedNames.add(fileName);
    onSave?.call();
    return 'content://media/external/images/media/${saved.length}';
  }

  @override
  Future<void> deleteImage(String uri) async {
    if (failDeleteUris.contains(uri)) {
      throw const GalleryException('fake delete failure');
    }
    deletedUris.add(uri);
  }
}

class FakeScanTempStore implements ScanTempStore {
  final List<String> deleted = <String>[];
  int purgeCalls = 0;

  @override
  Future<void> delete(Iterable<String> paths) async => deleted.addAll(paths);

  @override
  Future<void> purgeAll() async => purgeCalls++;
}
