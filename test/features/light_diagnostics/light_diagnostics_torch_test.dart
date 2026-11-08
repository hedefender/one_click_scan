import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/lighting/flash_mode.dart';
import 'package:one_click_scan/features/light_diagnostics/light_diagnostics_cubit.dart';

import '../../support/scan_fakes.dart';

/// Phase 6.2.1: the torch lines of the hidden diagnostics screen: lit or out,
/// the time since it was lit, and whether the latest live sample was taken
/// after it was lit and settled. The clock is injected.
void main() {
  late FakeCameraService camera;
  late LightDiagnosticsCubit cubit;
  late DateTime now;

  Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 5));

  setUp(() async {
    now = DateTime(2026, 1, 1, 12);
    camera = FakeCameraService(flashAvailable: true);
    cubit = LightDiagnosticsCubit(
      camera: camera,
      meter: FakeLightMeter(),
      tempStore: FakeScanTempStore(),
      now: () => now,
    );
    await cubit.start();
  });

  tearDown(() => cubit.close());

  test('Off: the torch is out and no time runs', () {
    expect(cubit.state.torchLit, isFalse);
    expect(cubit.state.litFor, isNull);
    expect(cubit.state.sampleAfterTorch, isFalse);
  });

  test('On lights it (Auto first, then On), the time starts at zero', () async {
    await cubit.cycleFlash(); // Auto
    expect(camera.torchLit, isFalse);
    expect(cubit.state.torchLit, isFalse);

    await cubit.cycleFlash(); // On
    expect(cubit.state.flashMode, FlashMode.on);
    expect(camera.torchLit, isTrue);
    expect(cubit.state.torchLit, isTrue);
    expect(cubit.state.litFor, Duration.zero);
  });

  test(
    'a sample is "after the lighting" only once the torch has settled',
    () async {
      await cubit.cycleFlash();
      await cubit.cycleFlash();

      now = now.add(const Duration(milliseconds: 100));
      camera.emitSample(FakeLightMeter.bright);
      await tick();
      expect(cubit.state.sampleAfterTorch, isFalse, reason: 'still settling');

      now = now.add(const Duration(seconds: 1));
      camera.emitSample(FakeLightMeter.bright);
      await tick();
      expect(cubit.state.sampleAfterTorch, isTrue);
    },
  );

  test('Off again: out, time and flag are cleared', () async {
    await cubit.cycleFlash();
    await cubit.cycleFlash();
    await cubit.cycleFlash(); // Off
    expect(camera.torchLit, isFalse);
    expect(cubit.state.torchLit, isFalse);
    expect(cubit.state.litFor, isNull);
    expect(cubit.state.sampleAfterTorch, isFalse);
  });

  test(
    'screen loses focus: out; back: lit again while the choice is On',
    () async {
      await cubit.cycleFlash();
      await cubit.cycleFlash();
      await cubit.onInactive();
      expect(camera.torchLit, isFalse);
      expect(cubit.state.torchLit, isFalse);

      await cubit.onResumed();
      expect(camera.torchLit, isTrue);
      expect(cubit.state.torchLit, isTrue);
    },
  );

  test('leaving the screen puts the torch out', () async {
    await cubit.cycleFlash();
    await cubit.cycleFlash();
    await cubit.close();
    expect(camera.torchLit, isFalse);
    expect(camera.isOpen, isFalse);
  });
}
