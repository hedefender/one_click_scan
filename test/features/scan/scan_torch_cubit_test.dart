import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:one_click_scan/core/logging/app_logger.dart';
import 'package:one_click_scan/data/datasources/key_value_flash_preference_store.dart';
import 'package:one_click_scan/domain/entities/scan_flow_mode.dart';
import 'package:one_click_scan/domain/entities/scan_mode.dart';
import 'package:one_click_scan/domain/lighting/flash_mode.dart';
import 'package:one_click_scan/domain/lighting/lighting_config.dart';
import 'package:one_click_scan/domain/lighting/low_light_policy.dart';
import 'package:one_click_scan/domain/ports/flash_preference_store.dart';
import 'package:one_click_scan/domain/ports/light_meter.dart';
import 'package:one_click_scan/services/camera/camera_service.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/domain/usecases/load_settings.dart';
import 'package:one_click_scan/domain/usecases/recognize_pages.dart';
import 'package:one_click_scan/domain/usecases/store_scan_pages.dart';
import 'package:one_click_scan/features/scan/scan_cubit.dart';
import 'package:one_click_scan/features/scan/scan_state.dart';
import 'package:one_click_scan/services/scan_files/scan_temp_store.dart';
import 'package:one_click_scan/services/storage_folder/storage_folder_picker.dart';

import '../../support/fakes.dart';
import '../../support/ocr_fakes.dart';
import '../../support/scan_fakes.dart';

/// Phase 6.2.1 (ADR-031): the torch of flash On. The state machine is tested
/// with the fake camera; the timeouts are injected as a few milliseconds, so
/// no test waits for the real 120 s (the real values are the config constants).
void main() {
  const idle = Duration(milliseconds: 240);
  const settle = Duration(milliseconds: 80);

  late FakeCameraService camera;
  late FakeLightMeter meter;
  late FakeScanTempStore temp;
  late InMemoryKeyValueStore kv;
  late GetIt container;
  late ScanCubit cubit;

  Future<void> wait(Duration d) => Future<void>.delayed(d);
  Future<void> tick() => wait(const Duration(milliseconds: 5));

  Future<void> setUpWith({
    bool flash = true,
    ScanFlowMode flow = ScanFlowMode.oneClick,
    double helpsMin = 40,
  }) async {
    camera = FakeCameraService(flashAvailable: flash);
    meter = FakeLightMeter();
    temp = FakeScanTempStore();
    kv = InMemoryKeyValueStore();
    final rig = OcrTestRig(enhancer: FakeEnhancer());
    container = await buildTestContainer(
      store: kv,
      camera: camera,
      scanFileStore: FakeScanFileStore(),
      scanTempStore: temp,
      ocr: rig.services,
      lightMeter: meter,
    );
    final repository = container<SettingsRepository>();
    await repository.save(
      (await repository.load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        scanFlowMode: flow,
      ),
    );
    cubit = ScanCubit(
      loadSettings: container<LoadSettings>(),
      folderPicker: container<StorageFolderPicker>(),
      camera: camera,
      storeScanPages: container<StoreScanPages>(),
      recognizePages: container<RecognizePages>(),
      tempStore: container<ScanTempStore>(),
      flashStore: container<FlashPreferenceStore>(),
      lightMeter: container<LightMeter>(),
      logger: container<AppLogger>(),
      torchIdleTimeout: idle,
      torchSettleDelay: settle,
      helpsMinPaperLevel: helpsMin,
    );
  }

  tearDown(() => cubit.close());

  /// Camera on screen, flash On, torch lit.
  Future<void> startWithTorch({ScanMode mode = ScanMode.single}) async {
    await cubit.start();
    cubit.setMode(mode);
    await cubit.setFlash(FlashMode.on);
    await tick();
    expect(camera.torchLit, isTrue, reason: 'precondition: torch is lit');
  }

  group('what lights the torch', () {
    test('On lights it, Auto and Off never do', () async {
      await setUpWith();
      await cubit.start();

      await cubit.setFlash(FlashMode.auto);
      await cubit.setFlash(FlashMode.off);
      await tick();
      expect(camera.torchLights, 0);
      expect(cubit.state.torchLit, isFalse);

      await cubit.setFlash(FlashMode.on);
      await tick();
      expect(camera.torchLit, isTrue);
      expect(cubit.state.torchLit, isTrue);
      expect(camera.torchLights, 1);
    });

    test('no flash on the phone: the torch is never asked for', () async {
      await setUpWith(flash: false);
      await cubit.start();
      await cubit.setFlash(FlashMode.on);
      await tick();
      expect(camera.torchLog, isEmpty);
      expect(cubit.state.torchLit, isFalse);
    });

    test('changing the flash to Off or to Auto puts it out at once', () async {
      await setUpWith();
      await startWithTorch();
      await cubit.setFlash(FlashMode.auto);
      expect(camera.torchLit, isFalse);
      expect(cubit.state.torchLit, isFalse);

      await cubit.setFlash(FlashMode.on);
      await tick();
      expect(camera.torchLit, isTrue);
      await cubit.setFlash(FlashMode.off);
      expect(camera.torchLit, isFalse);
    });

    test('a start with a stored value never opens with the torch on', () async {
      await setUpWith();
      await KeyValueFlashPreferenceStore(kv).save(FlashMode.on); // stored: Auto
      await cubit.start();
      await tick();
      expect(cubit.state.flashMode, FlashMode.auto);
      expect(camera.torchLights, 0);
    });

    test(
      'the shot is taken with the torch lit and it stays lit (Multi)',
      () async {
        await setUpWith();
        await startWithTorch(mode: ScanMode.multi);
        await wait(settle * 2);

        await cubit.capture();
        await tick();

        expect(camera.captured, hasLength(1));
        expect(camera.torchLit, isTrue);
        expect(camera.torchLights, 1, reason: 'no flicker around the shot');
      },
    );
  });

  group('the torch always goes out', () {
    test('leaving the camera screen (cancel and close)', () async {
      await setUpWith();
      await startWithTorch();
      await cubit.cancel();
      expect(camera.torchLit, isFalse);
      expect(camera.isOpen, isFalse);
    });

    test('dispose of the cubit', () async {
      await setUpWith();
      await startWithTorch();
      await cubit.close();
      expect(camera.torchLit, isFalse);
      expect(camera.isOpen, isFalse);
    });

    test('app in the background: out; back in front: lit again', () async {
      await setUpWith();
      await startWithTorch();

      await cubit.onBackground();
      expect(camera.torchLit, isFalse);
      expect(cubit.state.torchLit, isFalse);
      expect(cubit.state.phase, ScanPhase.paused);

      await cubit.onForeground();
      await tick();
      expect(cubit.state.flashMode, FlashMode.on);
      expect(camera.torchLit, isTrue, reason: 'the choice is still On');
    });

    test('lock screen / inactive: out at once, lit again when back', () async {
      await setUpWith();
      await startWithTorch();

      await cubit.onInactive();
      expect(camera.torchLit, isFalse);
      expect(camera.isOpen, isTrue, reason: 'only the torch goes out');

      await cubit.onForeground();
      await tick();
      expect(camera.torchLit, isTrue);
    });

    test('Single: the save after the shot (camera not visible)', () async {
      await setUpWith();
      await startWithTorch();
      await wait(settle * 2);

      await cubit.capture();
      await tick();

      expect(cubit.state.phase, ScanPhase.saved);
      expect(camera.torchLit, isFalse);
    });

    test('Multi: "Done" starts the save and the torch is out', () async {
      await setUpWith();
      await startWithTorch(mode: ScanMode.multi);
      await wait(settle * 2);
      await cubit.capture();
      await tick();
      expect(camera.torchLit, isTrue);

      await cubit.finish();
      await tick();

      expect(cubit.state.phase, ScanPhase.saved);
      expect(camera.torchLit, isFalse);
    });

    test('a dark shot waits for the user with the torch out, and it comes back '
        'with a new shot', () async {
      await setUpWith();
      meter.fallback = FakeLightMeter.dark;
      await startWithTorch();
      await wait(settle * 2);

      await cubit.capture();
      await tick();
      expect(cubit.state.lightPrompt, LightPrompt.singleShot);
      expect(camera.torchLit, isFalse, reason: 'a dialog covers the camera');

      await cubit.resolveLowLight(LowLightChoice.retake);
      await tick();
      expect(camera.torchLit, isTrue);
    });

    test('a failed shot: the torch goes out; a new try lights it and waits '
        'for the exposure', () async {
      await setUpWith();
      await startWithTorch(mode: ScanMode.multi);
      await wait(settle * 2);

      camera.failCapture = true;
      await cubit.capture();
      await tick();
      expect(cubit.state.captureFailed, isTrue);
      expect(camera.torchLit, isFalse);

      camera.failCapture = false;
      final watch = Stopwatch()..start();
      await cubit.capture();
      watch.stop();
      expect(camera.captured, hasLength(1));
      expect(camera.torchLit, isTrue);
      expect(
        watch.elapsed,
        greaterThanOrEqualTo(settle - const Duration(milliseconds: 15)),
        reason: 'the shot waits for a torch that was just lit',
      );
    });

    test('a camera that is opened again (rebind) starts with the torch out '
        'and the light comes back for On', () async {
      await setUpWith();
      await startWithTorch();

      // The camera is reopened: the real plugin starts with the torch out.
      await cubit.onBackground();
      expect(camera.torchLit, isFalse);
      await cubit.onForeground();
      await tick();

      expect(camera.openCalls, 2);
      expect(camera.torchLit, isTrue);
    });

    test('the camera cannot be opened: no torch', () async {
      await setUpWith();
      camera.openResults = [CameraOpenResult.unavailable];
      await cubit.start();
      await cubit.setFlash(FlashMode.on);
      await tick();
      expect(camera.torchLit, isFalse);
      expect(cubit.state.torchLit, isFalse);
    });
  });

  group('the torch goes out by itself after a time of no use', () {
    test(
      'Auto comes back, with a message flag, and Auto is remembered',
      () async {
        await setUpWith();
        await startWithTorch();

        await wait(idle + settle);

        expect(camera.torchLit, isFalse);
        expect(cubit.state.flashMode, FlashMode.auto);
        expect(cubit.state.torchIdleOff, isTrue);
        expect(KeyValueFlashPreferenceStore(kv).load(), FlashMode.auto);

        cubit.torchIdleOffShown();
        expect(cubit.state.torchIdleOff, isFalse);
      },
    );

    test('a shot starts the time again', () async {
      await setUpWith();
      await startWithTorch(mode: ScanMode.multi);
      await wait(const Duration(milliseconds: 150));

      await cubit.capture(); // waits for the settle, then the timer restarts
      await wait(const Duration(milliseconds: 150));
      expect(camera.torchLit, isTrue, reason: '300 ms in total, > idle');

      await wait(idle);
      expect(camera.torchLit, isFalse);
    });

    test('a tap to focus starts the time again', () async {
      await setUpWith();
      await startWithTorch();
      await wait(const Duration(milliseconds: 150));

      await cubit.focusAt(const Offset(0.5, 0.5));
      expect(camera.focusPoints, [const Offset(0.5, 0.5)]);
      await wait(const Duration(milliseconds: 150));
      expect(camera.torchLit, isTrue);

      await wait(idle);
      expect(camera.torchLit, isFalse);
    });

    test(
      'with the torch out nothing runs and the message is not set',
      () async {
        await setUpWith();
        await cubit.start();
        await wait(idle * 2);
        expect(cubit.state.torchIdleOff, isFalse);
      },
    );

    test('the real defaults are 120 s and 500 ms, in one place', () {
      // See LightingConfig: the cubit takes them when nothing is injected.
      expect(LightingConfig.torchIdleTimeout, const Duration(seconds: 120));
      expect(
        LightingConfig.torchSettleDelay,
        const Duration(milliseconds: 500),
      );
    });
  });

  group('the "low light" mark and the torch', () {
    test('samples right after the torch change are dropped; the mark '
        'changes only on fresh samples', () async {
      await setUpWith();
      await cubit.start();
      camera
        ..emitSample(FakeLightMeter.dark)
        ..emitSample(FakeLightMeter.dark);
      await tick();
      expect(cubit.state.lowLight, isTrue, reason: 'dark before the torch');

      await cubit.setFlash(FlashMode.on);
      await tick();
      // Old-light or half-adjusted frames: ignored, the mark neither shows
      // nor hides.
      camera
        ..emitSample(FakeLightMeter.bright)
        ..emitSample(FakeLightMeter.bright);
      await tick();
      expect(cubit.state.lowLight, isTrue);

      await wait(settle + const Duration(milliseconds: 30));
      camera.emitSample(FakeLightMeter.bright);
      await tick();
      expect(
        cubit.state.lowLight,
        isTrue,
        reason: 'one fresh sample is not enough (flicker guard)',
      );
      camera.emitSample(FakeLightMeter.bright);
      await tick();
      expect(cubit.state.lowLight, isFalse);
    });

    test(
      'a bright preview does not get a false mark from dark old samples',
      () async {
        await setUpWith();
        await cubit.start();
        await cubit.setFlash(FlashMode.on);
        await tick();
        camera
          ..emitSample(FakeLightMeter.dark)
          ..emitSample(FakeLightMeter.dark);
        await tick();
        expect(cubit.state.lowLight, isFalse, reason: 'settling');

        await wait(settle + const Duration(milliseconds: 30));
        camera
          ..emitSample(FakeLightMeter.bright)
          ..emitSample(FakeLightMeter.bright);
        await tick();
        expect(cubit.state.lowLight, isFalse);
      },
    );
  });

  group('so dark that the correction will not help (second threshold)', () {
    Future<void> shoot(ScanMode mode) async {
      meter.fallback = FakeLightMeter.dark; // paper level 20
      await cubit.start();
      cubit.setMode(mode);
      await cubit.capture();
      await tick();
    }

    test('below the "helps" level: a retake is advised first', () async {
      await setUpWith(helpsMin: 30);
      await shoot(ScanMode.single);
      expect(cubit.state.lightPrompt, LightPrompt.singleShot);
      expect(cubit.state.darkNeedsRetake, isTrue);
    });

    test('above the "helps" level (and still dark): the usual text', () async {
      await setUpWith(helpsMin: 10);
      await shoot(ScanMode.single);
      expect(cubit.state.lightPrompt, LightPrompt.singleShot);
      expect(cubit.state.darkNeedsRetake, isFalse);
    });

    test('preview mode: the flag reaches the page list as well', () async {
      await setUpWith(helpsMin: 30, flow: ScanFlowMode.preview);
      await shoot(ScanMode.single);
      expect(cubit.state.phase, ScanPhase.saved);
      expect(cubit.state.darkPages, hasLength(1));
      expect(cubit.state.darkNeedsRetake, isTrue);
    });

    test(
      'Multi: the summary asks for the retake when one page is too dark',
      () async {
        await setUpWith(helpsMin: 30);
        await shoot(ScanMode.multi);
        await cubit.finish();
        expect(cubit.state.lightPrompt, LightPrompt.summary);
        expect(cubit.state.darkNeedsRetake, isTrue);
      },
    );

    test('a bright shot is never "too dark"', () async {
      await setUpWith(helpsMin: 30);
      await cubit.start();
      await cubit.capture();
      expect(cubit.state.darkNeedsRetake, isFalse);
    });
  });
}
