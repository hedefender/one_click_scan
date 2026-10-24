import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/core/config/app_config.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';
import 'package:one_click_scan/domain/entities/scan_mode.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/domain/ports/image_header_reader.dart';
import 'package:one_click_scan/domain/usecases/recognize_pages.dart';
import 'package:one_click_scan/services/camera/camera_service.dart';
import 'package:one_click_scan/features/scan/scan_cubit.dart';
import 'package:one_click_scan/features/scan/scan_state.dart';

import '../../support/fakes.dart';
import '../../support/ocr_fakes.dart';
import '../../support/scan_fakes.dart';

void main() {
  late OcrTestRig rig;
  late FakeCameraService camera;
  late FakeScanFileStore store;
  late FakeScanTempStore temp;
  late ScanCubit cubit;

  Future<void> setUpWith({String deviceLanguage = 'el'}) async {
    rig = OcrTestRig();
    camera = FakeCameraService();
    store = FakeScanFileStore();
    temp = FakeScanTempStore();
    final container = await buildTestContainer(
      config: AppConfig.forDeviceLanguage(deviceLanguage),
      camera: camera,
      scanFileStore: store,
      scanTempStore: temp,
      ocr: rig.services,
    );
    final repository = container<SettingsRepository>();
    await repository.save(
      (await repository.load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
      ),
    );
    cubit = container<ScanCubit>();
  }

  tearDown(() => cubit.close());

  test('opening the camera preloads the models of the chosen pack', () async {
    await setUpWith();

    await cubit.start();
    await pumpEventQueue();

    expect(rig.engine.preloaded, ['greek']);
  });

  test('an English device preloads the latin pack', () async {
    await setUpWith(deviceLanguage: 'en');

    await cubit.start();
    await pumpEventQueue();

    expect(rig.engine.preloaded, ['latin']);
  });

  test('no preload when the camera cannot start', () async {
    await setUpWith();
    camera.openResults = [CameraOpenResult.permissionDenied];

    await cubit.start();
    await pumpEventQueue();

    expect(rig.engine.preloaded, isEmpty);
  });

  test(
    'Multi Page: each page is read right after its shot, before Done',
    () async {
      await setUpWith();
      await cubit.start();
      cubit.setMode(ScanMode.multi);

      await cubit.capture();
      await pumpEventQueue();
      expect(rig.engine.recognized, hasLength(1));

      await cubit.capture();
      await pumpEventQueue();
      expect(rig.engine.recognized, hasLength(2));
      expect(cubit.state.phase, ScanPhase.ready); // still shooting
      expect(cubit.state.ocr, isNull); // handed over only when saved
    },
  );

  test(
    'Done hands the reading to the result with every page, in order',
    () async {
      await setUpWith();
      await cubit.start();
      cubit.setMode(ScanMode.multi);
      await cubit.capture();
      await cubit.capture();
      await cubit.capture();

      await cubit.finish();

      expect(cubit.state.phase, ScanPhase.saved);
      final done = await cubit.state.ocr!.finished;
      expect(done.pages.map((p) => p.key), camera.captured);
      expect(done.pages.every((p) => p.outcome is OcrSuccess), isTrue);
    },
  );

  test('Single Page: the shot is saved and its text is read', () async {
    await setUpWith();
    await cubit.start();

    await cubit.capture();

    expect(cubit.state.phase, ScanPhase.saved);
    final done = await cubit.state.ocr!.finished;
    expect(done.pages, hasLength(1));
    expect(rig.engine.recognized, hasLength(1));
  });

  test('deleting the last shot removes its reading', () async {
    await setUpWith();
    rig.engine.gate = Completer<void>();
    await cubit.start();
    cubit.setMode(ScanMode.multi);
    await cubit.capture();
    await cubit.capture();
    await pumpEventQueue();

    await cubit.deleteLast();
    rig.engine.gate!.complete();
    await cubit.finish();

    final done = await cubit.state.ocr!.finished;
    expect(done.pages.map((p) => p.key), [camera.captured.first]);
  });

  test('a failing OCR never fails the scan', () async {
    await setUpWith();
    rig.engine.respond = (_) => const OcrFailed(OcrFailureReason.engineError);
    await cubit.start();
    cubit.setMode(ScanMode.multi);
    await cubit.capture();

    await cubit.finish();

    expect(cubit.state.phase, ScanPhase.saved);
    expect(store.files('pictures'), hasLength(1));
    final done = await cubit.state.ocr!.finished;
    expect(done.pages.single.outcome, isA<OcrFailed>());
  });

  test('a photo above 50 MP: the scan is saved, the reading fails as too '
      'large', () async {
    await setUpWith();
    rig.header.headers['cache/fake_page_1.jpg'] = const ImageHeader(
      width: 12240,
      height: 16320,
      orientation: 1,
    );
    await cubit.start();

    await cubit.capture();

    expect(cubit.state.phase, ScanPhase.saved);
    final done = await cubit.state.ocr!.finished;
    expect(
      done.pages.single.outcome,
      const OcrFailed(OcrFailureReason.imageTooLarge),
    );
  });

  test(
    'cancelling the scan stops the reading and removes working copies',
    () async {
      await setUpWith();
      rig.engine.gate = Completer<void>();
      await cubit.start();
      cubit.setMode(ScanMode.multi);
      await cubit.capture();
      await pumpEventQueue();
      expect(rig.workStore.files, isNotEmpty);

      await cubit.cancel();
      await pumpEventQueue();

      expect(rig.workStore.files, isEmpty);
      expect(rig.engine.releaseCalls, 1);
    },
  );

  test('after Done the session is the screen\'s to dispose, not the '
      'cubit\'s', () async {
    await setUpWith();
    await cubit.start();
    await cubit.capture(); // single page: saved

    await cubit.close();

    // Closing the cubit after the save must not touch the reading.
    expect(rig.engine.releaseCalls, 0);
    final session = cubit.state.ocr!;
    await session.finished;
    await session.dispose();
    expect(rig.engine.releaseCalls, 1);
  });

  test('the OcrSession type is what the result screen receives', () async {
    await setUpWith();
    await cubit.start();
    await cubit.capture();

    expect(cubit.state.ocr, isA<OcrSession>());
  });
}
