import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/core/errors/app_exceptions.dart';
import 'package:one_click_scan/domain/entities/scan_mode.dart';
import 'package:one_click_scan/domain/entities/stored_scan.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/scan/scan_cubit.dart';
import 'package:one_click_scan/features/scan/scan_state.dart';
import 'package:one_click_scan/services/camera/camera_service.dart';

import '../../support/fakes.dart';
import '../../support/scan_fakes.dart';

void main() {
  late FakeStorageFolderPicker picker;
  late FakeCameraService camera;
  late FakeScanFileStore store;
  late FakeGalleryService gallery;
  late FakeScanTempStore temp;
  late SettingsRepository repository;
  late ScanCubit cubit;

  Future<void> setUpWith({
    List<CameraOpenResult> openResults = const [CameraOpenResult.ready],
    bool withFolder = true,
    bool saveToGallery = false,
  }) async {
    picker = FakeStorageFolderPicker();
    camera = FakeCameraService(openResults: openResults);
    store = FakeScanFileStore();
    gallery = FakeGalleryService();
    temp = FakeScanTempStore();
    final container = await buildTestContainer(
      picker: picker,
      camera: camera,
      scanFileStore: store,
      gallery: gallery,
      scanTempStore: temp,
    );
    repository = container<SettingsRepository>();
    await repository.save(
      (await repository.load()).copyWith(
        firstRunCompleted: true,
        storageFolder: withFolder ? testFolder : null,
        saveToGallery: saveToGallery,
      ),
    );
    cubit = container<ScanCubit>();
  }

  tearDown(() => cubit.close());

  group('start', () {
    test('opens the camera when the folder is accessible', () async {
      await setUpWith();
      await cubit.start();

      expect(cubit.state.phase, ScanPhase.ready);
      expect(camera.openCalls, 1);
    });

    test('lost folder access: no camera, no scan', () async {
      await setUpWith();
      picker.accessGranted = false;
      await cubit.start();

      expect(cubit.state.phase, ScanPhase.folderUnavailable);
      expect(camera.openCalls, 0);
    });

    test('no folder at all behaves like a lost folder', () async {
      await setUpWith(withFolder: false);
      await cubit.start();

      expect(cubit.state.phase, ScanPhase.folderUnavailable);
      expect(camera.openCalls, 0);
    });

    test('denied permission is reported and can be retried', () async {
      await setUpWith(
        openResults: [
          CameraOpenResult.permissionDenied,
          CameraOpenResult.ready,
        ],
      );
      await cubit.start();
      expect(cubit.state.phase, ScanPhase.permissionDenied);

      await cubit.retryCamera();
      expect(cubit.state.phase, ScanPhase.ready);
    });

    test('unavailable camera is reported', () async {
      await setUpWith(openResults: [CameraOpenResult.unavailable]);
      await cubit.start();

      expect(cubit.state.phase, ScanPhase.cameraUnavailable);
    });

    test('app settings can be opened from the denied state', () async {
      await setUpWith(openResults: [CameraOpenResult.permissionDenied]);
      await cubit.start();
      await cubit.openAppSettings();

      expect(camera.openSettingsCalls, 1);
    });
  });

  group('single page', () {
    test('a shot is stored at once and the scan is saved', () async {
      await setUpWith();
      await cubit.start();
      await cubit.capture();

      expect(cubit.state.phase, ScanPhase.saved);
      expect(cubit.state.result!.pictures.map((p) => p.fileName), [
        '2026-10-21_19-05-12_1.jpg',
      ]);
      expect(store.files('pictures'), ['2026-10-21_19-05-12_1.jpg']);
      expect(camera.isOpen, isFalse);
    });

    test('Gallery copy follows the setting', () async {
      await setUpWith(saveToGallery: true);
      await cubit.start();
      await cubit.capture();

      expect(gallery.saved, hasLength(1));
      expect(
        cubit.state.result!.pictures.single.gallery,
        GalleryCopyStatus.saved,
      );
    });

    test('a failed Gallery copy still saves the scan', () async {
      await setUpWith(saveToGallery: true);
      gallery.fail = true;
      await cubit.start();
      await cubit.capture();

      expect(cubit.state.phase, ScanPhase.saved);
      expect(cubit.state.result!.hasGalleryFailures, isTrue);
    });
  });

  group('multi page', () {
    Future<void> startMulti() async {
      await cubit.start();
      cubit.setMode(ScanMode.multi);
    }

    test('shots are collected, nothing is written until Done', () async {
      await setUpWith();
      await startMulti();
      await cubit.capture();
      await cubit.capture();

      expect(cubit.state.pages, hasLength(2));
      expect(cubit.state.phase, ScanPhase.ready);
      expect(store.copyCalls, 0);
      expect(store.folders, isEmpty);
    });

    test('Done stores all pages with one stem', () async {
      await setUpWith();
      await startMulti();
      await cubit.capture();
      await cubit.capture();
      await cubit.finish();

      expect(cubit.state.phase, ScanPhase.saved);
      expect(store.files('pictures'), [
        '2026-10-21_19-05-12_1.jpg',
        '2026-10-21_19-05-12_2.jpg',
      ]);
    });

    test(
      'the last page can be deleted and its cache file is removed',
      () async {
        await setUpWith();
        await startMulti();
        await cubit.capture();
        await cubit.capture();
        await cubit.capture();
        await cubit.deleteLast();

        expect(cubit.state.pages, hasLength(2));
        expect(temp.deleted, [camera.captured.last]);

        await cubit.finish();
        expect(store.files('pictures'), hasLength(2));
      },
    );

    test('the mode is locked while pages exist', () async {
      await setUpWith();
      await startMulti();
      await cubit.capture();
      cubit.setMode(ScanMode.single);

      expect(cubit.state.mode, ScanMode.multi);
    });

    test('Done does nothing without pages', () async {
      await setUpWith();
      await startMulti();
      await cubit.finish();

      expect(cubit.state.phase, ScanPhase.ready);
    });

    test('cancel leaves nothing behind in the folder or the cache', () async {
      await setUpWith();
      await startMulti();
      await cubit.capture();
      await cubit.capture();
      await cubit.cancel();

      expect(store.folders, isEmpty);
      expect(temp.deleted, camera.captured);
      expect(cubit.state.pages, isEmpty);
      expect(camera.isOpen, isFalse);
    });

    test('closing the cubit mid-scan also cleans the cache', () async {
      await setUpWith();
      await startMulti();
      await cubit.capture();
      await cubit.close();

      expect(temp.deleted, camera.captured);
      expect(store.folders, isEmpty);
    });

    test(
      'after saving, the cache files are kept for the result screen',
      () async {
        await setUpWith();
        await startMulti();
        await cubit.capture();
        await cubit.finish();
        await cubit.close();

        expect(temp.deleted, isEmpty);
      },
    );
  });

  group('failures', () {
    test('a failed write keeps the pages and a retry succeeds', () async {
      await setUpWith();
      await cubit.start();
      cubit.setMode(ScanMode.multi);
      await cubit.capture();
      await cubit.capture();
      store.failOnCopyNumber = 2;
      await cubit.finish();

      expect(cubit.state.phase, ScanPhase.saveFailed);
      expect(cubit.state.pages, hasLength(2));
      expect(store.files('pictures'), isEmpty);
      expect(temp.deleted, isEmpty);

      store.failOnCopyNumber = null;
      await cubit.save();

      expect(cubit.state.phase, ScanPhase.saved);
      expect(store.files('pictures'), hasLength(2));
    });

    test('single page: a failed write can be retried', () async {
      await setUpWith();
      await cubit.start();
      store.failOnCopyNumber = 1;
      await cubit.capture();
      expect(cubit.state.phase, ScanPhase.saveFailed);

      store.failOnCopyNumber = null;
      await cubit.save();
      expect(cubit.state.phase, ScanPhase.saved);
    });

    test('folder access lost while saving keeps the pages', () async {
      await setUpWith();
      await cubit.start();
      cubit.setMode(ScanMode.multi);
      await cubit.capture();
      picker.accessGranted = false;
      await cubit.finish();

      expect(cubit.state.phase, ScanPhase.folderUnavailable);
      expect(cubit.state.pages, hasLength(1));
      expect(store.folders, isEmpty);
    });

    test('the store reporting no access is treated as a lost folder', () async {
      await setUpWith();
      await cubit.start();
      cubit.setMode(ScanMode.multi);
      await cubit.capture();
      store.failEverything = ScanStoreFailure.noAccess;
      await cubit.finish();

      expect(cubit.state.phase, ScanPhase.folderUnavailable);
    });

    test('after the folder is fixed a single-page scan is finished', () async {
      await setUpWith();
      await cubit.start();
      picker.accessGranted = false;
      await cubit.capture();
      expect(cubit.state.phase, ScanPhase.folderUnavailable);

      picker.accessGranted = true;
      await cubit.retryAfterFolderFix();

      expect(cubit.state.phase, ScanPhase.saved);
      expect(store.files('pictures'), hasLength(1));
    });

    test('a failed shot is reported and the user can shoot again', () async {
      await setUpWith();
      await cubit.start();
      cubit.setMode(ScanMode.multi);
      camera.failCapture = true;
      await cubit.capture();

      expect(cubit.state.captureFailed, isTrue);
      expect(cubit.state.phase, ScanPhase.ready);
      expect(cubit.state.pages, isEmpty);

      camera.failCapture = false;
      await cubit.capture();
      expect(cubit.state.captureFailed, isFalse);
      expect(cubit.state.pages, hasLength(1));
    });
  });

  group('lifecycle', () {
    test('the camera is released in the background and reopened', () async {
      await setUpWith();
      await cubit.start();
      await cubit.onBackground();

      expect(cubit.state.phase, ScanPhase.paused);
      expect(camera.isOpen, isFalse);

      await cubit.onForeground();
      expect(cubit.state.phase, ScanPhase.ready);
      expect(camera.isOpen, isTrue);
    });

    test('pages survive a trip to the background', () async {
      await setUpWith();
      await cubit.start();
      cubit.setMode(ScanMode.multi);
      await cubit.capture();
      await cubit.onBackground();
      await cubit.onForeground();

      expect(cubit.state.pages, hasLength(1));
    });

    test('coming back re-checks a denied permission', () async {
      await setUpWith(
        openResults: [
          CameraOpenResult.permissionDenied,
          CameraOpenResult.ready,
        ],
      );
      await cubit.start();
      await cubit.onForeground();

      expect(cubit.state.phase, ScanPhase.ready);
    });

    test('going to the background while starting does nothing', () async {
      await setUpWith();
      await cubit.onBackground();

      expect(cubit.state.phase, ScanPhase.starting);
      expect(camera.closeCalls, 0);
    });
  });
  group('cancel while the pictures are written (ADR-028)', () {
    test('Multi: nothing stays, the shots stay, back to the camera', () async {
      await setUpWith(saveToGallery: true);
      await cubit.start();
      cubit.setMode(ScanMode.multi);
      await cubit.capture();
      await cubit.capture();
      store.onCopied = (n) {
        if (n == 1) cubit.cancelSaving();
      };

      await cubit.finish();

      expect(cubit.state.phase, ScanPhase.ready);
      expect(cubit.state.saveCancelled, isTrue);
      expect(cubit.state.pages, hasLength(2));
      expect(store.files('pictures'), isEmpty);
      expect(gallery.saved, isEmpty);
      expect(temp.deleted, isEmpty);
      expect(camera.isOpen, isTrue);
    });

    test('Multi: the same shots can be saved afterwards', () async {
      await setUpWith();
      await cubit.start();
      cubit.setMode(ScanMode.multi);
      await cubit.capture();
      store.onCopied = (_) => cubit.cancelSaving();
      await cubit.finish();
      store.onCopied = null;

      await cubit.finish();

      expect(cubit.state.phase, ScanPhase.saved);
      expect(store.files('pictures'), hasLength(1));
    });

    test('Single: nothing stays and the one shot is dropped', () async {
      await setUpWith();
      await cubit.start();
      store.onCopied = (_) => cubit.cancelSaving();

      await cubit.capture();

      expect(cubit.state.phase, ScanPhase.ready);
      expect(cubit.state.saveCancelled, isTrue);
      expect(cubit.state.pages, isEmpty);
      expect(store.files('pictures'), isEmpty);
      expect(temp.deleted, ['cache/fake_page_1.jpg']);
    });

    test('the undo arrow is off while the pictures are written', () async {
      await setUpWith();
      await cubit.start();
      cubit.setMode(ScanMode.multi);
      await cubit.capture();
      await cubit.capture();
      store.onCopied = (_) => cubit.deleteLast();

      await cubit.finish();

      expect(cubit.state.phase, ScanPhase.saved);
      expect(store.files('pictures'), hasLength(2));
    });

    test('a cancel outside the saving does nothing', () async {
      await setUpWith();
      await cubit.start();
      cubit.cancelSaving();

      expect(cubit.state.phase, ScanPhase.ready);
      expect(cubit.state.saveCancelled, isFalse);
    });
  });
}
