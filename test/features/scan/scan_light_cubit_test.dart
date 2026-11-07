import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/data/datasources/key_value_flash_preference_store.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';
import 'package:one_click_scan/domain/entities/scan_flow_mode.dart';
import 'package:one_click_scan/domain/entities/scan_mode.dart';
import 'package:one_click_scan/domain/lighting/flash_mode.dart';
import 'package:one_click_scan/domain/lighting/low_light_policy.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/scan/scan_cubit.dart';
import 'package:one_click_scan/features/scan/scan_state.dart';

import '../../support/fakes.dart';
import '../../support/ocr_fakes.dart';
import '../../support/scan_fakes.dart';

/// Phase 6.2 on the camera screen's cubit: the flash (what is remembered), the
/// "low light" mark of the preview, and what a dark shot does in each mode.
void main() {
  late FakeCameraService camera;
  late FakeScanFileStore store;
  late FakeScanTempStore temp;
  late FakeLightMeter meter;
  late InMemoryKeyValueStore kv;
  late OcrTestRig rig;
  late FakeEnhancer enhancer;
  late ScanCubit cubit;

  Future<void> setUpWith({
    ScanFlowMode flow = ScanFlowMode.oneClick,
    bool flash = true,
    FlashMode stored = FlashMode.off,
  }) async {
    camera = FakeCameraService(flashAvailable: flash);
    store = FakeScanFileStore();
    temp = FakeScanTempStore();
    meter = FakeLightMeter();
    kv = InMemoryKeyValueStore();
    enhancer = FakeEnhancer();
    rig = OcrTestRig(enhancer: enhancer);
    await KeyValueFlashPreferenceStore(kv).save(stored);
    final container = await buildTestContainer(
      store: kv,
      camera: camera,
      scanFileStore: store,
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
    cubit = container<ScanCubit>();
  }

  tearDown(() => cubit.close());

  group('flash', () {
    test('no flash on the phone: the button is not shown', () async {
      await setUpWith(flash: false);
      await cubit.start();

      expect(cubit.state.hasFlash, isFalse);
      await cubit.cycleFlash();
      expect(camera.flashSet, isEmpty);
    });

    test('the default is Off and it is applied to the camera', () async {
      await setUpWith();
      await cubit.start();

      expect(cubit.state.hasFlash, isTrue);
      expect(cubit.state.flashMode, FlashMode.off);
      expect(camera.flashSet.last, FlashMode.off);
    });

    test('Off and Auto are remembered', () async {
      await setUpWith();
      await cubit.start();

      await cubit.cycleFlash(); // Auto
      expect(cubit.state.flashMode, FlashMode.auto);
      expect(KeyValueFlashPreferenceStore(kv).load(), FlashMode.auto);

      await cubit.setFlash(FlashMode.off);
      expect(KeyValueFlashPreferenceStore(kv).load(), FlashMode.off);
    });

    test('On works now but the next start opens in Auto', () async {
      await setUpWith();
      await cubit.start();
      await cubit.setFlash(FlashMode.on);
      expect(cubit.state.flashMode, FlashMode.on);
      expect(camera.flashSet.last, FlashMode.on);
      await cubit.close();

      // A new use of the app: the same stored values, a new cubit.
      final next = (await buildTestContainer(
        store: kv,
        camera: FakeCameraService(flashAvailable: true),
        scanTempStore: temp,
      ))<ScanCubit>();
      addTearDown(next.close);
      final repo = (await buildTestContainer(store: kv))<SettingsRepository>();
      await repo.save(
        (await repo.load()).copyWith(
          firstRunCompleted: true,
          storageFolder: testFolder,
        ),
      );
      await next.start();
      expect(next.state.flashMode, FlashMode.auto);
    });

    test('On survives the app going to the background and back', () async {
      await setUpWith();
      await cubit.start();
      await cubit.setFlash(FlashMode.on);

      await cubit.onBackground();
      await cubit.onForeground();

      expect(cubit.state.flashMode, FlashMode.on);
      expect(camera.flashSet.last, FlashMode.on);
    });
  });

  group('low light mark of the preview', () {
    test(
      'two dark samples in a row switch the mark on, bright ones off',
      () async {
        await setUpWith();
        await cubit.start();
        expect(camera.analysisStarts, 1);

        camera.emitSample(FakeLightMeter.dark);
        camera.emitSample(FakeLightMeter.dark);
        await Future<void>.delayed(Duration.zero);
        expect(cubit.state.lowLight, isTrue);

        camera.emitSample(FakeLightMeter.bright);
        camera.emitSample(FakeLightMeter.bright);
        await Future<void>.delayed(Duration.zero);
        expect(cubit.state.lowLight, isFalse);
      },
    );

    test('the analysis stops when the camera is released', () async {
      await setUpWith();
      await cubit.start();
      final stops = camera.analysisStops;

      await cubit.onBackground();

      expect(camera.analysisStops, greaterThan(stops));
    });
  });

  group('One Click, Single Page', () {
    Future<void> shootDark() async {
      meter.fallback = FakeLightMeter.dark;
      await cubit.start();
      await cubit.capture();
    }

    test(
      'a dark shot stops the flow with the dialog; nothing is stored',
      () async {
        await setUpWith();
        await shootDark();

        expect(cubit.state.lightPrompt, LightPrompt.singleShot);
        expect(cubit.state.phase, isNot(ScanPhase.saved));
        expect(store.files('pictures'), isEmpty);
        expect(cubit.state.canCapture, isFalse);
      },
    );

    test('a bright shot goes on without a question', () async {
      await setUpWith();
      await cubit.start();
      await cubit.capture();

      expect(cubit.state.phase, ScanPhase.saved);
      expect(cubit.state.lightPrompt, LightPrompt.none);
    });

    test('New shot: back to the camera, no file anywhere', () async {
      await setUpWith();
      await shootDark();
      final path = cubit.state.pages.single.path;

      await cubit.resolveLowLight(LowLightChoice.retake);

      expect(cubit.state.lightPrompt, LightPrompt.none);
      expect(cubit.state.pages, isEmpty);
      expect(cubit.state.darkPages, isEmpty);
      expect(cubit.state.phase, ScanPhase.ready);
      expect(store.files('pictures'), isEmpty);
      expect(temp.deleted, contains(path));
      expect(cubit.state.canCapture, isTrue);
    });

    test('Continue anyway: the dark shot is stored and sent on', () async {
      await setUpWith();
      await shootDark();

      await cubit.resolveLowLight(LowLightChoice.continueAnyway);

      expect(cubit.state.phase, ScanPhase.saved);
      expect(store.files('pictures'), hasLength(1));
      expect(enhancer.sources, isEmpty);
      expect(cubit.state.darkPages, isEmpty);
    });

    test(
      'Continue with correction: the page is corrected in the queue',
      () async {
        await setUpWith();
        rig.engine.respond = (image) => OcrSuccess(
          fakeResult([
            fakeLine(
              enhancer.targets.contains(image.path)
                  ? 'one two three four'
                  : 'one two',
            ),
          ]),
        );
        await shootDark();

        await cubit.resolveLowLight(LowLightChoice.continueWithEnhancement);

        expect(cubit.state.phase, ScanPhase.saved);
        final done = await cubit.state.ocr!.finished;
        expect(done.pages.single.enhancement, isNotNull);
        expect(enhancer.sources, hasLength(1));
        await cubit.state.ocr!.dispose();
      },
    );
  });

  group('One Click, Multi Page', () {
    Future<void> startMulti() async {
      await cubit.start();
      cubit.setMode(ScanMode.multi);
    }

    test('a dark shot only marks the page: the rhythm is not broken', () async {
      await setUpWith();
      await startMulti();
      final dark = 'cache/fake_page_1.jpg';
      meter.byPath[dark] = FakeLightMeter.dark;

      await cubit.capture();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.lightPrompt, LightPrompt.none);
      expect(cubit.state.canCapture, isTrue);
      expect(cubit.state.darkPages, [dark]);
      expect(cubit.state.darkBarPage, dark);
    });

    test('the bar offers a new shot: the same as the undo', () async {
      await setUpWith();
      await startMulti();
      meter.byPath['cache/fake_page_1.jpg'] = FakeLightMeter.dark;
      await cubit.capture();
      await Future<void>.delayed(Duration.zero);

      await cubit.retakeDarkPage();

      expect(cubit.state.pages, isEmpty);
      expect(cubit.state.darkPages, isEmpty);
      expect(cubit.state.darkBarPage, isNull);
    });

    test('the next shot closes the bar; the page stays flagged', () async {
      await setUpWith();
      await startMulti();
      meter.byPath['cache/fake_page_1.jpg'] = FakeLightMeter.dark;
      await cubit.capture();
      await Future<void>.delayed(Duration.zero);

      await cubit.capture();
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.darkBarPage, isNull);
      expect(cubit.state.darkPages, ['cache/fake_page_1.jpg']);
    });

    test(
      'Done with a flagged page: the summary, never a silent send',
      () async {
        await setUpWith();
        await startMulti();
        meter.byPath['cache/fake_page_1.jpg'] = FakeLightMeter.dark;
        await cubit.capture();
        await Future<void>.delayed(Duration.zero);
        await cubit.capture();
        await Future<void>.delayed(Duration.zero);

        await cubit.finish();

        expect(cubit.state.lightPrompt, LightPrompt.summary);
        expect(cubit.state.phase, isNot(ScanPhase.saved));
        expect(store.files('pictures'), isEmpty);
      },
    );

    test('the summary: back to the camera keeps the pages', () async {
      await setUpWith();
      await startMulti();
      meter.byPath['cache/fake_page_1.jpg'] = FakeLightMeter.dark;
      await cubit.capture();
      await Future<void>.delayed(Duration.zero);
      await cubit.finish();

      await cubit.resolveLowLight(LowLightChoice.retake);

      expect(cubit.state.lightPrompt, LightPrompt.none);
      expect(cubit.state.pages, hasLength(1));
      expect(cubit.state.canCapture, isTrue);
    });

    test('the summary: continue anyway sends and clears the marks', () async {
      await setUpWith();
      await startMulti();
      meter.byPath['cache/fake_page_1.jpg'] = FakeLightMeter.dark;
      await cubit.capture();
      await Future<void>.delayed(Duration.zero);
      await cubit.finish();

      await cubit.resolveLowLight(LowLightChoice.continueAnyway);

      expect(cubit.state.phase, ScanPhase.saved);
      expect(store.files('pictures'), hasLength(1));
    });

    test('Done with only bright pages saves at once', () async {
      await setUpWith();
      await startMulti();
      await cubit.capture();
      await cubit.finish();

      expect(cubit.state.phase, ScanPhase.saved);
    });

    test('an undone dark page is no longer flagged', () async {
      await setUpWith();
      await startMulti();
      meter.byPath['cache/fake_page_1.jpg'] = FakeLightMeter.dark;
      await cubit.capture();
      await Future<void>.delayed(Duration.zero);
      cubit.dismissDarkBar();

      await cubit.deleteLast();

      expect(cubit.state.darkPages, isEmpty);
    });
  });

  group('preview mode', () {
    test(
      'a dark shot never interrupts; it is handed to the result screen',
      () async {
        await setUpWith(flow: ScanFlowMode.preview);
        meter.fallback = FakeLightMeter.dark;
        await cubit.start();

        await cubit.capture();

        expect(cubit.state.lightPrompt, LightPrompt.none);
        expect(cubit.state.phase, ScanPhase.saved);
        expect(cubit.state.darkPages, hasLength(1));
        await cubit.state.ocr?.dispose();
      },
    );

    test('Multi: Done goes on without the summary', () async {
      await setUpWith(flow: ScanFlowMode.preview);
      await cubit.start();
      cubit.setMode(ScanMode.multi);
      meter.byPath['cache/fake_page_1.jpg'] = FakeLightMeter.dark;
      await cubit.capture();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.darkBarPage, isNull);

      await cubit.finish();

      expect(cubit.state.phase, ScanPhase.saved);
      expect(cubit.state.darkPages, ['cache/fake_page_1.jpg']);
      await cubit.state.ocr?.dispose();
    });
  });

  test('a shot that cannot be measured is never called dark', () async {
    await setUpWith();
    meter.fallback = null;
    await cubit.start();
    await cubit.capture();

    expect(cubit.state.phase, ScanPhase.saved);
  });
}
