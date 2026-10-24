import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/ocr/ocr_keys.dart';
import 'package:one_click_scan/features/scan/scan_keys.dart';

import '../../support/fakes.dart';
import '../../support/ocr_fakes.dart';
import '../../support/scan_fakes.dart';

/// Scan -> result -> OCR check screen, with the real cubits and a fake engine.
void main() {
  late OcrTestRig rig;

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    rig = OcrTestRig();
    final store = InMemoryKeyValueStore();
    Future<GetIt> build() => buildTestContainer(
      store: store,
      camera: FakeCameraService(),
      scanFileStore: FakeScanFileStore(),
      gallery: FakeGalleryService(),
      scanTempStore: FakeScanTempStore(),
      ocr: rig.services,
    );
    final seed = await build();
    await seed<SettingsRepository>().save(
      (await seed<SettingsRepository>().load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        mailProvider: MailProviderId.gmail,
        senderAccount: 'sender@example.com',
      ),
    );
    final container = await build();
    await tester.pumpWidget(OneClickScanApp(container: container));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeKeys.scanAndSend));
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  testWidgets('single page: the result offers the OCR check, which shows '
      'the text', (tester) async {
    await pumpHome(tester);
    rig.engine.respond = (_) =>
        OcrSuccess(fakeResult([fakeLine('Σύνολο 12,50', confidence: 0.97)]));

    await tapKey(tester, ScanKeys.capture);
    expect(find.text('Scan saved'), findsOneWidget);
    expect(find.byKey(ScanKeys.resultOcr), findsOneWidget);

    await tapKey(tester, ScanKeys.resultOcr);

    expect(find.text('OCR text'), findsOneWidget);
    expect(find.text('Σύνολο 12,50'), findsOneWidget);
    expect(find.byKey(OcrKeys.summary), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('Multi page: the check screen has one page per shot', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.text('Multi page'));
    await tester.pumpAndSettle();
    await tapKey(tester, ScanKeys.capture);
    await tapKey(tester, ScanKeys.capture);
    await tapKey(tester, ScanKeys.done);
    await tapKey(tester, ScanKeys.resultOcr);

    expect(find.text('Page 1 of 2'), findsOneWidget);
    await tapKey(tester, OcrKeys.nextPage);
    expect(find.text('Page 2 of 2'), findsOneWidget);
    expect(rig.engine.recognized, hasLength(2));
  });

  testWidgets('leaving the result removes the working copies and frees the '
      'engine', (tester) async {
    await pumpHome(tester);
    await tapKey(tester, ScanKeys.capture);
    await tester.pumpAndSettle();
    expect(rig.workStore.files, isNotEmpty);

    await tapKey(tester, ScanKeys.resultBack);

    expect(rig.workStore.files, isEmpty);
    expect(rig.engine.releaseCalls, 1);
  });

  testWidgets('a failed reading is shown on the check screen, the scan is '
      'still saved', (tester) async {
    await pumpHome(tester);
    rig.engine.respond = (_) => const OcrFailed(OcrFailureReason.engineError);

    await tapKey(tester, ScanKeys.capture);
    expect(find.text('Scan saved'), findsOneWidget);
    await tapKey(tester, ScanKeys.resultOcr);

    expect(find.text('Reading this page failed.'), findsOneWidget);
  });
}
