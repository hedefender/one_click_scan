import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/scan/scan_keys.dart';

import '../test/support/fakes.dart';
import '../test/support/scan_fakes.dart';

/// Runs on a real Android emulator/device. The camera and the folder are
/// fakes (no webcam, no SAF UI): this covers the app flow end to end with
/// real rendering and navigation. The real camera is covered by
/// `camera_smoke_test.dart`, the real folder writer by the manual checklist
/// in docs/PHASE_1_VALIDATION.md.
///
/// Run on the Claude Code emulator only:
///   flutter test integration_test/scan_flow_test.dart -d `<emulator-id>`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home, SCAN & SEND, multi page, Done: two named files', (
    tester,
  ) async {
    final store = FakeScanFileStore();
    final container = await buildTestContainer(
      camera: FakeCameraService(),
      scanFileStore: store,
      scanTempStore: FakeScanTempStore(),
    );
    final repository = container<SettingsRepository>();
    await repository.save(
      (await repository.load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
      ),
    );

    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(HomeKeys.scanAndSend));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Multi page'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pumpAndSettle();
    expect(find.text('Pages: 2'), findsOneWidget);

    await tester.tap(find.byKey(ScanKeys.done));
    await tester.pumpAndSettle();

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
    expect(store.files('pictures'), [
      '2026-10-21_19-05-12_1.jpg',
      '2026-10-21_19-05-12_2.jpg',
    ]);

    await tester.tap(find.byKey(ScanKeys.resultBack));
    await tester.pumpAndSettle();
    expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);
  });
}
