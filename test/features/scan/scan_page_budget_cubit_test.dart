import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/core/logging/app_logger.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/scan_flow_mode.dart';
import 'package:one_click_scan/domain/entities/scan_mode.dart';
import 'package:one_click_scan/domain/ports/flash_preference_store.dart';
import 'package:one_click_scan/domain/ports/light_meter.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/domain/scan/page_budget_config.dart';
import 'package:one_click_scan/domain/usecases/load_settings.dart';
import 'package:one_click_scan/domain/usecases/recognize_pages.dart';
import 'package:one_click_scan/domain/usecases/store_scan_pages.dart';
import 'package:one_click_scan/features/scan/scan_cubit.dart';
import 'package:one_click_scan/services/scan_files/scan_temp_store.dart';
import 'package:one_click_scan/services/storage_folder/storage_folder_picker.dart';

import '../../support/fakes.dart';
import '../../support/ocr_fakes.dart';
import '../../support/scan_fakes.dart';

const _mb = 1024 * 1024;

/// Phase 6.3 (ADR-032): the page budget of a Multi Page scan, through the real
/// cubit with the fake camera and the fake OCR rig. The sizes of the pictures
/// come from the work store of the rig, the limits from the injected config and
/// provider, so no test needs a real photo.
void main() {
  late OcrTestRig rig;
  late FakeCameraService camera;
  late ScanCubit cubit;

  /// [config] and [provider] reach the cubit; [sizeOfPage] is the size every
  /// prepared page gets.
  Future<void> setUpWith({
    PageBudgetConfig config = const PageBudgetConfig(
      perPageOverheadBytes: 0,
      fixedOverheadBytes: 0,
    ),
    int sizeOfPage = 1 * _mb,
    MailProviderId? provider = MailProviderId.gmail,
    ScanFlowMode flow = ScanFlowMode.oneClick,
  }) async {
    rig = OcrTestRig();
    rig.workStore.defaultBytes = sizeOfPage;
    camera = FakeCameraService();
    final container = await buildTestContainer(
      camera: camera,
      scanFileStore: FakeScanFileStore(),
      scanTempStore: FakeScanTempStore(),
      ocr: rig.services,
    );
    final repository = container<SettingsRepository>();
    await repository.save(
      (await repository.load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        scanFlowMode: flow,
        mailProvider: provider,
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
      budgetConfig: config,
    );
    await cubit.start();
    cubit.setMode(ScanMode.multi);
  }

  tearDown(() => cubit.close());

  /// One shot and the time for the background preparation to report its size.
  Future<void> shoot() async {
    await cubit.capture();
    await pumpEventQueue();
  }

  group('the sizes reach the budget', () {
    test('the size of each prepared page is in the state', () async {
      await setUpWith(sizeOfPage: 2 * _mb);

      await shoot();
      await shoot();

      expect(cubit.state.pageBytes.length, 2);
      expect(cubit.state.pageBytes.values, everyElement(2 * _mb));
      expect(cubit.state.budget!.pageCount, 2);
    });

    test('the limit moves with the measured sizes', () async {
      await setUpWith(sizeOfPage: 1 * _mb);
      await shoot();
      final light = cubit.state.budget!.maxPages;

      rig.workStore.defaultBytes = 6 * _mb;
      await shoot();
      await shoot();

      expect(cubit.state.budget!.maxPages, lessThan(light));
    });

    test('Single Page has no budget', () async {
      await setUpWith();
      cubit.setMode(ScanMode.single);

      expect(cubit.state.budget, isNull);
      expect(cubit.state.pageLimitReached, isFalse);
      expect(cubit.state.canCapture, isTrue);
    });
  });

  group('at the limit', () {
    test('the hard maximum stops the shots', () async {
      await setUpWith(
        sizeOfPage: 1000,
        config: const PageBudgetConfig(
          hardMaxPages: 3,
          perPageOverheadBytes: 0,
          fixedOverheadBytes: 0,
        ),
      );

      await shoot();
      await shoot();
      expect(cubit.state.canCapture, isTrue);
      await shoot();

      expect(cubit.state.pages.length, 3);
      expect(cubit.state.pageLimitReached, isTrue);
      expect(cubit.state.canCapture, isFalse);

      // A fourth tap does nothing: no page, no camera call.
      final shots = camera.captured.length;
      await shoot();
      expect(cubit.state.pages.length, 3);
      expect(camera.captured.length, shots);
    });

    test('heavy pages reach the limit of the provider before 25', () async {
      // Gmail takes about 18.2 MB: pages of 5 MB fit 3 times (18.2 * 0.9 / 5).
      await setUpWith(sizeOfPage: 5 * _mb);

      await shoot();
      await shoot();
      await shoot();

      expect(cubit.state.budget!.maxPages, 3);
      expect(cubit.state.canCapture, isFalse);
    });

    test('"Done" stays possible at the limit', () async {
      await setUpWith(
        sizeOfPage: 1000,
        config: const PageBudgetConfig(
          hardMaxPages: 2,
          perPageOverheadBytes: 0,
          fixedOverheadBytes: 0,
        ),
      );
      await shoot();
      await shoot();

      expect(cubit.state.canCapture, isFalse);
      expect(cubit.state.canFinish, isTrue);
    });

    test('deleting the last page gives the shot back', () async {
      await setUpWith(
        sizeOfPage: 1000,
        config: const PageBudgetConfig(
          hardMaxPages: 2,
          perPageOverheadBytes: 0,
          fixedOverheadBytes: 0,
        ),
      );
      await shoot();
      await shoot();
      expect(cubit.state.canCapture, isFalse);

      await cubit.deleteLast();

      expect(cubit.state.pages.length, 1);
      expect(cubit.state.canCapture, isTrue);
    });

    test(
      'a very heavy page lowers the limit below the pages: none removed',
      () async {
        await setUpWith(sizeOfPage: 200 * 1024);
        for (var i = 0; i < 6; i++) {
          await shoot();
        }
        expect(cubit.state.pages.length, 6);

        rig.workStore.defaultBytes = 30 * _mb;
        await shoot();

        final budget = cubit.state.budget!;
        expect(cubit.state.pages.length, 7, reason: 'no page was removed');
        expect(budget.maxPages, lessThan(7));
        expect(budget.reached, isTrue);
        expect(cubit.state.canCapture, isFalse);
      },
    );
  });

  group('the provider', () {
    test('the same pages fit fewer times with a 14.6 MB provider', () async {
      await setUpWith(sizeOfPage: 3 * _mb, provider: MailProviderId.gmail);
      await shoot();
      final gmail = cubit.state.budget!.maxPages;
      await cubit.close();

      await setUpWith(sizeOfPage: 3 * _mb, provider: MailProviderId.outlook);
      await shoot();
      final outlook = cubit.state.budget!.maxPages;

      expect(gmail, 5);
      expect(outlook, 4);
    });

    test('without a provider the strictest limit is used', () async {
      await setUpWith(sizeOfPage: 3 * _mb, provider: null);
      await shoot();

      expect(cubit.state.budget!.maxPages, 4);
      expect(cubit.state.budget!.limitBytes / 1e6, closeTo(14.6, 0.1));
    });
  });

  group('the preview flow counts the same', () {
    test('the cubit does not depend on One Click or preview', () async {
      for (final flow in ScanFlowMode.values) {
        await setUpWith(sizeOfPage: 5 * _mb, flow: flow);
        await shoot();
        await shoot();
        await shoot();

        expect(cubit.state.canCapture, isFalse, reason: flow.name);
        await cubit.close();
      }
    });
  });
}
