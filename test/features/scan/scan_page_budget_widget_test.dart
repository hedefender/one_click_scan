import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/data/datasources/key_value_multi_page_hint_store.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/scan_flow_mode.dart';
import 'package:one_click_scan/domain/ports/multi_page_hint_store.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/scan/scan_keys.dart';

import '../../support/fakes.dart';
import '../../support/mail_fakes.dart';
import '../../support/ocr_fakes.dart';
import '../../support/pdf_fakes.dart';
import '../../support/scan_fakes.dart';

/// Phase 6.3 on the camera screen: the "n/XX" counter, the "still fits"
/// message, the shot blocked at the limit (both flows), the busy capture
/// button, and the first-open hint of Multi Page.
void main() {
  late FakeCameraService camera;
  late OcrTestRig rig;
  late InMemoryKeyValueStore kv;

  Future<void> pumpScan(
    WidgetTester tester, {
    ScanFlowMode flow = ScanFlowMode.oneClick,
    int pageBytes = 3100000, // Gmail (about 18.2 MB) takes 5 pages of it
    bool hintSeen = true,
  }) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    camera = FakeCameraService();
    rig = OcrTestRig();
    rig.workStore.defaultBytes = pageBytes;
    kv = InMemoryKeyValueStore();
    final pdf = PdfTestRig();
    final mail = MailTestRig()..storePassword();
    Future<GetIt> build() => buildTestContainer(
      store: kv,
      camera: camera,
      scanFileStore: FakeScanFileStore(),
      scanTempStore: FakeScanTempStore(),
      ocr: rig.services,
      lightMeter: FakeLightMeter(),
      pdf: pdf.services,
      mail: mail.services,
      multiHintSeen: hintSeen,
    );
    final seed = await build();
    await seed<SettingsRepository>().save(
      (await seed<SettingsRepository>().load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        mailProvider: MailProviderId.gmail,
        senderAccount: testAccount,
        scanFlowMode: flow,
      ),
    );
    await tester.pumpWidget(OneClickScanApp(container: await build()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeKeys.scanAndSend));
    await tester.pumpAndSettle();
  }

  Future<void> goMulti(WidgetTester tester) async {
    await tester.tap(find.text('Multi page'));
    await tester.pumpAndSettle();
  }

  Future<void> shoot(WidgetTester tester) async {
    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pumpAndSettle();
  }

  String counter(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(ScanKeys.pageCounter).first).data!;

  for (final flow in ScanFlowMode.values) {
    group('Multi in ${flow.name}', () {
      testWidgets('only the number before page 5 (small pages)', (
        tester,
      ) async {
        await pumpScan(tester, flow: flow, pageBytes: 200 * 1024);
        await goMulti(tester);

        for (var i = 1; i <= 4; i++) {
          await shoot(tester);
          expect(counter(tester), 'Pages: $i');
        }
        expect(find.byKey(ScanKeys.pageBudgetNote), findsNothing);
      });

      testWidgets('n/XX from page 5', (tester) async {
        await pumpScan(tester, flow: flow, pageBytes: 200 * 1024);
        await goMulti(tester);

        for (var i = 1; i <= 5; i++) {
          await shoot(tester);
        }
        expect(counter(tester), 'Pages: 5/25');
      });

      testWidgets('earlier when the pages use half of the limit, and the '
          '"still fits" message with two pages left', (tester) async {
        await pumpScan(tester, flow: flow);
        await goMulti(tester);

        await shoot(tester);
        await shoot(tester);
        expect(counter(tester), 'Pages: 2');
        await shoot(tester); // 3 x 3.1 MB is over half of 18.2 MB
        expect(counter(tester), 'Pages: 3/5');
        expect(find.byKey(ScanKeys.pageBudgetNote), findsOneWidget);
        expect(
          find.text('About 2 more pages will fit in the email (approximate).'),
          findsOneWidget,
        );
      });

      testWidgets('at the limit the shot is blocked and the screen says why', (
        tester,
      ) async {
        await pumpScan(tester, flow: flow);
        await goMulti(tester);
        for (var i = 1; i <= 5; i++) {
          await shoot(tester);
        }

        expect(counter(tester), 'Pages: 5/5');
        expect(find.byKey(ScanKeys.pageLimitReached), findsOneWidget);
        expect(
          find.textContaining('go over the email size limit'),
          findsOneWidget,
        );
        final shots = camera.captured.length;

        await tester.tap(find.byKey(ScanKeys.capture));
        await tester.pumpAndSettle();
        expect(camera.captured.length, shots, reason: 'no sixth shot');
        expect(find.byKey(ScanKeys.done), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byKey(ScanKeys.done)).onPressed,
          isNotNull,
          reason: 'Done stays possible',
        );
      });

      testWidgets('the undo gives the shot back', (tester) async {
        await pumpScan(tester, flow: flow);
        await goMulti(tester);
        for (var i = 1; i <= 5; i++) {
          await shoot(tester);
        }
        expect(find.byKey(ScanKeys.pageLimitReached), findsOneWidget);

        await tester.tap(find.byKey(ScanKeys.deleteLast));
        await tester.pumpAndSettle();

        expect(find.byKey(ScanKeys.pageLimitReached), findsNothing);
        await shoot(tester);
        expect(camera.captured.length, 6);
      });
    });
  }

  testWidgets('Single Page shows no budget', (tester) async {
    await pumpScan(tester);
    expect(find.byKey(ScanKeys.pageCounter), findsNothing);
    expect(find.byKey(ScanKeys.pageBudgetNote), findsNothing);
  });

  group('the capture button while a shot is taken', () {
    testWidgets('shows that it is busy, and is idle again after', (
      tester,
    ) async {
      await pumpScan(tester, pageBytes: 200 * 1024);
      await goMulti(tester);
      expect(find.byKey(ScanKeys.captureBusy), findsNothing);
      expect(find.bySemanticsLabel('Take photo'), findsOneWidget);

      camera.captureGate = Future<void>.delayed(
        const Duration(milliseconds: 300),
      );
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(ScanKeys.captureBusy), findsOneWidget);
      expect(find.bySemanticsLabel('Taking photo...'), findsOneWidget);
      // A second tap while busy does nothing.
      final shots = camera.captured.length;
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pump(const Duration(milliseconds: 50));
      expect(camera.captured.length, lessThanOrEqualTo(shots + 1));

      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      expect(find.byKey(ScanKeys.captureBusy), findsNothing);
      expect(camera.captured.length, 1, reason: 'one shot only');
      expect(find.bySemanticsLabel('Take photo'), findsOneWidget);
    });
  });

  group('the first time Multi Page is chosen', () {
    testWidgets('the hint shows once, with the lines of the guide', (
      tester,
    ) async {
      await pumpScan(tester, hintSeen: false);
      expect(find.byKey(ScanKeys.multiHint), findsNothing);

      await goMulti(tester);

      expect(find.byKey(ScanKeys.multiHint), findsOneWidget);
      expect(find.textContaining('Tap "Done"'), findsOneWidget);
      expect(find.textContaining('up to 25 pages'), findsOneWidget);
      expect(find.textContaining('are deleted'), findsOneWidget);
      expect(kv.getBool(KeyValueMultiPageHintStore.keySeen), isTrue);

      await tester.tap(find.byKey(ScanKeys.multiHintOk));
      await tester.pumpAndSettle();
      expect(find.byKey(ScanKeys.multiHint), findsNothing);

      // Back to Single and to Multi again: no second hint.
      await tester.tap(find.text('Single page'));
      await tester.pumpAndSettle();
      await goMulti(tester);
      expect(find.byKey(ScanKeys.multiHint), findsNothing);
    });

    testWidgets('not shown again on the next start of the app', (tester) async {
      await pumpScan(tester, hintSeen: false);
      await goMulti(tester);
      await tester.tap(find.byKey(ScanKeys.multiHintOk));
      await tester.pumpAndSettle();

      final next = await buildTestContainer(
        store: kv,
        camera: FakeCameraService(),
        multiHintSeen: false,
        ocr: rig.services,
        lightMeter: FakeLightMeter(),
      );
      expect(next<MultiPageHintStore>().seen, isTrue);
    });

    testWidgets('Single Page never shows it', (tester) async {
      await pumpScan(tester, hintSeen: false);
      expect(find.byKey(ScanKeys.multiHint), findsNothing);
      expect(kv.getBool(KeyValueMultiPageHintStore.keySeen), isNull);
    });
  });
}
