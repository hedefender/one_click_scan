import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/domain/entities/app_language.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/scan/scan_keys.dart';
import 'package:one_click_scan/features/settings/settings_keys.dart';
import 'package:one_click_scan/services/camera/camera_service.dart';

import '../../support/fakes.dart';
import '../../support/scan_fakes.dart';

void main() {
  late FakeStorageFolderPicker picker;
  late FakeCameraService camera;
  late FakeScanFileStore store;
  late FakeGalleryService gallery;
  late FakeScanTempStore temp;
  late SettingsRepository settingsRepository;

  /// Starts the app on home with a finished wizard stored.
  Future<void> pumpHome(
    WidgetTester tester, {
    List<CameraOpenResult> openResults = const [CameraOpenResult.ready],
    bool saveToGallery = false,
    Size size = const Size(800, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    picker = FakeStorageFolderPicker();
    camera = FakeCameraService(openResults: openResults);
    store = FakeScanFileStore();
    gallery = FakeGalleryService();
    temp = FakeScanTempStore();
    final kv = InMemoryKeyValueStore();

    Future<GetIt> build() => buildTestContainer(
      store: kv,
      picker: picker,
      camera: camera,
      scanFileStore: store,
      gallery: gallery,
      scanTempStore: temp,
    );

    final seed = await build();
    await seed<SettingsRepository>().save(
      (await seed<SettingsRepository>().load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        mailProvider: MailProviderId.gmail,
        senderAccount: 'sender@example.com',
        saveToGallery: saveToGallery,
      ),
    );
    final container = await build();
    settingsRepository = container<SettingsRepository>();
    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();
  }

  Future<void> openScan(WidgetTester tester) async {
    await tester.tap(find.byKey(HomeKeys.scanAndSend));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  Future<void> selectMulti(WidgetTester tester) async {
    await tester.tap(find.text('Multi page'));
    await tester.pumpAndSettle();
  }

  testWidgets('SCAN & SEND opens the camera screen', (tester) async {
    await pumpHome(tester);
    await openScan(tester);

    expect(find.byKey(ScanKeys.preview), findsOneWidget);
    expect(find.byKey(ScanKeys.modeSelector), findsOneWidget);
    expect(find.byKey(ScanKeys.capture), findsOneWidget);
    expect(find.byKey(ScanKeys.done), findsNothing);
  });

  group('layout', () {
    // Portrait and landscape, small phone, big phone, tablet-like window.
    const sizes = <String, Size>{
      'small portrait': Size(360, 640),
      'portrait': Size(411, 891),
      'small landscape': Size(640, 360),
      'landscape': Size(891, 411),
      'wide window': Size(1280, 600),
    };

    for (final entry in sizes.entries) {
      testWidgets('${entry.key}: no overflow, buttons work', (tester) async {
        await pumpHome(tester, size: entry.value);
        await openScan(tester);

        // The preview fills the whole screen under the floating controls.
        final preview = tester.getRect(find.byKey(ScanKeys.preview));
        expect(preview.size, entry.value);
        expect(find.byKey(ScanKeys.modeSelector), findsOneWidget);
        expect(find.byKey(ScanKeys.capture), findsOneWidget);

        await selectMulti(tester);
        await tapKey(tester, ScanKeys.capture);
        await tapKey(tester, ScanKeys.capture);
        await tapKey(tester, ScanKeys.capture);
        expect(find.text('Pages: 3'), findsOneWidget);
        expect(find.byKey(ScanKeys.thumbnails), findsOneWidget);

        await tapKey(tester, ScanKeys.deleteLast);
        expect(find.text('Pages: 2'), findsOneWidget);

        // Every control is on screen and does not sit on another one.
        final screen = Offset.zero & entry.value;
        final rects = <Rect>[
          for (final key in [
            ScanKeys.capture,
            ScanKeys.done,
            ScanKeys.deleteLast,
            ScanKeys.modeSelector,
          ])
            tester.getRect(find.byKey(key)),
        ];
        for (final rect in rects) {
          expect(screen.contains(rect.topLeft), isTrue);
          expect(
            screen.contains(rect.bottomRight - const Offset(1, 1)),
            isTrue,
          );
        }
        for (var i = 0; i < rects.length; i++) {
          for (var j = i + 1; j < rects.length; j++) {
            expect(rects[i].overlaps(rects[j]), isFalse, reason: '$i vs $j');
          }
        }

        await tapKey(tester, ScanKeys.done);
        expect(find.text('Scan saved'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('landscape puts the controls on the right side', (
      tester,
    ) async {
      await pumpHome(tester, size: const Size(891, 411));
      await openScan(tester);

      final capture = tester.getCenter(find.byKey(ScanKeys.capture));
      expect(capture.dx, greaterThan(891 * 0.8));
    });

    testWidgets('portrait puts the controls at the bottom', (tester) async {
      await pumpHome(tester, size: const Size(411, 891));
      await openScan(tester);

      final capture = tester.getCenter(find.byKey(ScanKeys.capture));
      expect(capture.dy, greaterThan(891 * 0.8));
    });

    testWidgets('rotating in the middle of Multi keeps the pages', (
      tester,
    ) async {
      await pumpHome(tester, size: const Size(411, 891));
      await openScan(tester);
      await selectMulti(tester);
      await tapKey(tester, ScanKeys.capture);
      await tapKey(tester, ScanKeys.capture);

      tester.view.physicalSize = const Size(891, 411);
      await tester.pumpAndSettle();
      expect(find.text('Pages: 2'), findsOneWidget);

      await tapKey(tester, ScanKeys.capture);
      tester.view.physicalSize = const Size(411, 891);
      await tester.pumpAndSettle();
      expect(find.text('Pages: 3'), findsOneWidget);
      expect(camera.openCalls, 1);
    });

    testWidgets('the result screen fits in landscape', (tester) async {
      await pumpHome(tester, size: const Size(640, 360));
      await openScan(tester);
      await tapKey(tester, ScanKeys.capture);

      expect(find.text('Scan saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('single page: one tap stores the shot and shows the result', (
    tester,
  ) async {
    await pumpHome(tester);
    await openScan(tester);
    await tapKey(tester, ScanKeys.capture);

    expect(find.text('Scan saved'), findsOneWidget);
    expect(
      find.byKey(ScanKeys.resultFile('2026-10-21_19-05-12_1.jpg')),
      findsOneWidget,
    );
    expect(find.text('1 file saved in "Scans/pictures"'), findsOneWidget);
    expect(store.files('pictures'), ['2026-10-21_19-05-12_1.jpg']);
  });

  testWidgets('multi page: thumbnails, delete last, Done, result', (
    tester,
  ) async {
    await pumpHome(tester);
    await openScan(tester);
    await selectMulti(tester);

    await tapKey(tester, ScanKeys.capture);
    await tapKey(tester, ScanKeys.capture);
    await tapKey(tester, ScanKeys.capture);
    expect(find.byKey(ScanKeys.thumbnails), findsOneWidget);
    expect(find.text('Pages: 3'), findsOneWidget);
    expect(store.copyCalls, 0);

    await tapKey(tester, ScanKeys.deleteLast);
    expect(find.text('Pages: 2'), findsOneWidget);

    await tapKey(tester, ScanKeys.done);
    expect(find.text('Scan saved'), findsOneWidget);
    expect(find.text('2 files saved in "Scans/pictures"'), findsOneWidget);
    expect(
      find.byKey(ScanKeys.resultFile('2026-10-21_19-05-12_1.jpg')),
      findsOneWidget,
    );
    expect(
      find.byKey(ScanKeys.resultFile('2026-10-21_19-05-12_2.jpg')),
      findsOneWidget,
    );

    await tapKey(tester, ScanKeys.resultBack);
    expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);
    expect(temp.deleted, containsAll(camera.captured.take(2)));
  });

  testWidgets('the mode switch is locked once a page was taken', (
    tester,
  ) async {
    await pumpHome(tester);
    await openScan(tester);
    await selectMulti(tester);
    await tapKey(tester, ScanKeys.capture);

    await tester.tap(find.text('Single page'));
    await tester.pumpAndSettle();

    expect(find.byKey(ScanKeys.done), findsOneWidget);
    expect(find.text('Pages: 1'), findsOneWidget);
  });

  testWidgets('leaving a multi scan asks first; Stay keeps the pages', (
    tester,
  ) async {
    await pumpHome(tester);
    await openScan(tester);
    await selectMulti(tester);
    await tapKey(tester, ScanKeys.capture);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Discard this scan?'), findsOneWidget);

    await tapKey(tester, ScanKeys.dialogStay);
    expect(find.text('Pages: 1'), findsOneWidget);
  });

  testWidgets('Discard leaves, deletes the cache and writes nothing', (
    tester,
  ) async {
    await pumpHome(tester);
    await openScan(tester);
    await selectMulti(tester);
    await tapKey(tester, ScanKeys.capture);
    await tapKey(tester, ScanKeys.capture);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tapKey(tester, ScanKeys.dialogDiscard);

    expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);
    expect(store.folders, isEmpty);
    expect(temp.deleted, camera.captured);
    expect(camera.isOpen, isFalse);
  });

  testWidgets('leaving without pages does not ask', (tester) async {
    await pumpHome(tester);
    await openScan(tester);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);
  });

  testWidgets('denied camera permission: message, retry, app settings', (
    tester,
  ) async {
    await pumpHome(
      tester,
      openResults: [CameraOpenResult.permissionDenied, CameraOpenResult.ready],
    );
    await openScan(tester);

    expect(
      find.text(
        'Camera access is needed to scan documents. Allow it to continue.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(ScanKeys.preview), findsNothing);

    await tapKey(tester, ScanKeys.openAppSettings);
    expect(camera.openSettingsCalls, 1);

    await tapKey(tester, ScanKeys.retryCamera);
    expect(find.byKey(ScanKeys.preview), findsOneWidget);
  });

  testWidgets('unavailable camera shows a message', (tester) async {
    await pumpHome(tester, openResults: [CameraOpenResult.unavailable]);
    await openScan(tester);

    expect(
      find.text('The camera is not available on this device.'),
      findsOneWidget,
    );
  });

  testWidgets('lost folder: message and a way to Settings, no camera', (
    tester,
  ) async {
    await pumpHome(tester);
    picker.accessGranted = false;
    await openScan(tester);

    expect(find.text('The folder is no longer accessible'), findsWidgets);
    expect(camera.openCalls, 0);
    expect(find.byKey(ScanKeys.capture), findsOneWidget);

    await tester.tap(find.byKey(ScanKeys.folderOpenSettings));
    await tester.pumpAndSettle();
    expect(find.byKey(SettingsKeys.changeFolder), findsOneWidget);

    // Fix the folder in Settings and come back: the camera starts.
    picker.accessGranted = true;
    await tapKey(tester, SettingsKeys.changeFolder);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(ScanKeys.preview), findsOneWidget);
    expect(camera.openCalls, 1);
  });

  testWidgets('failed write keeps the pages and Try again stores them', (
    tester,
  ) async {
    await pumpHome(tester);
    await openScan(tester);
    await selectMulti(tester);
    await tapKey(tester, ScanKeys.capture);
    store.failOnCopyNumber = 1;
    await tapKey(tester, ScanKeys.done);

    expect(
      find.textContaining('The pages could not be saved to your folder'),
      findsOneWidget,
    );
    expect(find.text('Pages: 1'), findsOneWidget);
    expect(store.files('pictures'), isEmpty);

    store.failOnCopyNumber = null;
    await tapKey(tester, ScanKeys.retrySave);
    expect(find.text('Scan saved'), findsOneWidget);
    expect(store.files('pictures'), ['2026-10-21_19-05-12_1.jpg']);
  });

  testWidgets('a failed shot shows a message and the user can retry', (
    tester,
  ) async {
    await pumpHome(tester);
    await openScan(tester);
    await selectMulti(tester);
    camera.failCapture = true;
    await tapKey(tester, ScanKeys.capture);

    expect(find.byKey(ScanKeys.captureFailed), findsOneWidget);

    camera.failCapture = false;
    await tapKey(tester, ScanKeys.capture);
    expect(find.byKey(ScanKeys.captureFailed), findsNothing);
    expect(find.text('Pages: 1'), findsOneWidget);
  });

  testWidgets('result marks Gallery copies when the switch is on', (
    tester,
  ) async {
    await pumpHome(tester, saveToGallery: true);
    await openScan(tester);
    await tapKey(tester, ScanKeys.capture);

    expect(find.text('Copy saved to Gallery'), findsOneWidget);
    expect(gallery.saved, hasLength(1));
  });

  testWidgets('result shows a failed Gallery copy without failing the scan', (
    tester,
  ) async {
    await pumpHome(tester, saveToGallery: true);
    gallery.fail = true;
    await openScan(tester);
    await tapKey(tester, ScanKeys.capture);

    expect(find.text('Scan saved'), findsOneWidget);
    expect(find.text('Gallery copy failed'), findsOneWidget);
    expect(store.files('pictures'), hasLength(1));
  });

  testWidgets('result shows no Gallery note when the switch is off', (
    tester,
  ) async {
    await pumpHome(tester);
    await openScan(tester);
    await tapKey(tester, ScanKeys.capture);

    expect(find.text('Copy saved to Gallery'), findsNothing);
    expect(find.text('Gallery copy failed'), findsNothing);
  });

  testWidgets('the scan screens follow the app language', (tester) async {
    await pumpHome(tester);
    final repo = settingsRepository;
    await repo.save((await repo.load()).copyWith(language: AppLanguage.el));
    await tester.pumpAndSettle();

    await openScan(tester);
    expect(find.text('Μία σελίδα'), findsOneWidget);
    expect(find.text('Πολλές σελίδες'), findsOneWidget);

    await tapKey(tester, ScanKeys.capture);
    expect(find.text('Η σάρωση αποθηκεύτηκε'), findsOneWidget);
    expect(
      find.text('Αποθηκεύτηκε 1 αρχείο στο "Scans/pictures"'),
      findsOneWidget,
    );
  });
  group('Phase 5.1: cancel while the pictures are written', () {
    Future<void> doneWithStoreHeld(WidgetTester tester) async {
      await pumpHome(tester);
      await openScan(tester);
      await selectMulti(tester);
      await tapKey(tester, ScanKeys.capture);
      await tapKey(tester, ScanKeys.capture);
      store.copyGate = Completer<void>();
      await tester.tap(find.byKey(ScanKeys.done));
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> systemBack(WidgetTester tester) async {
      final message = const JSONMethodCodec().encodeMethodCall(
        const MethodCall('popRoute'),
      );
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/navigation',
        message,
        (_) {},
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('Cancel: nothing is stored, the shots and the camera stay', (
      tester,
    ) async {
      await doneWithStoreHeld(tester);

      expect(find.byKey(ScanKeys.saving), findsOneWidget);
      // The undo arrow is off while the work runs.
      final undo = tester.widget<IconButton>(find.byKey(ScanKeys.deleteLast));
      expect(undo.onPressed, isNull);
      await tester.tap(find.byKey(ScanKeys.saveCancel));
      store.copyGate!.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(ScanKeys.saving), findsNothing);
      expect(find.byKey(ScanKeys.saveCancelled), findsOneWidget);
      expect(
        find.text(
          'Saving stopped. Nothing was saved and your shots are still here.',
        ),
        findsOneWidget,
      );
      expect(store.files('pictures'), isEmpty);
      expect(find.byKey(ScanKeys.capture), findsOneWidget);
      expect(find.text('Pages: 2'), findsOneWidget);
    });

    testWidgets('Back asks first; "Continue" lets the saving finish', (
      tester,
    ) async {
      await doneWithStoreHeld(tester);

      await systemBack(tester);
      expect(find.text('Stop the processing?'), findsOneWidget);
      await tester.tap(find.byKey(ScanKeys.stopContinue));
      await tester.pump(const Duration(milliseconds: 100));
      store.copyGate!.complete();
      await tester.pumpAndSettle();

      expect(store.files('pictures'), hasLength(2));
      expect(find.byKey(ScanKeys.resultSummary), findsOneWidget);
    });

    testWidgets('Back with "Stop" is the Cancel button', (tester) async {
      await doneWithStoreHeld(tester);

      await systemBack(tester);
      await tester.tap(find.byKey(ScanKeys.stopConfirm));
      await tester.pump(const Duration(milliseconds: 100));
      store.copyGate!.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(ScanKeys.saveCancelled), findsOneWidget);
      expect(store.files('pictures'), isEmpty);
      expect(find.byKey(ScanKeys.capture), findsOneWidget); // not left
    });
  });
}
