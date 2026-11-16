import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/core/errors/app_exceptions.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/scan_flow_mode.dart';
import 'package:one_click_scan/domain/mail/mail_outcome.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/features/home/home_keys.dart';
import 'package:one_click_scan/features/scan/scan_keys.dart';

import '../../support/fakes.dart';
import '../../support/mail_fakes.dart';
import '../../support/ocr_fakes.dart';
import '../../support/pdf_fakes.dart';
import '../../support/scan_fakes.dart';

/// The screen stays on while the result screen works (reading, PDF, send) and
/// is given back in EVERY other case (A1-004): success, error, cancel, discard
/// and leaving the screen. With a fake that records each call.
void main() {
  late OcrTestRig rig;
  late PdfTestRig pdf;
  late MailTestRig mail;
  late FakeScreenAwake awake;

  Future<void> pumpScan(
    WidgetTester tester, {
    required ScanFlowMode flowMode,
    bool capture = true,
  }) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    rig = OcrTestRig();
    pdf = PdfTestRig();
    mail = MailTestRig()..storePassword();
    awake = FakeScreenAwake();
    final values = InMemoryKeyValueStore();
    final store = FakeScanFileStore();
    Future<GetIt> build() => buildTestContainer(
      store: values,
      scanFileStore: store,
      gallery: FakeGalleryService(),
      ocr: rig.services,
      pdf: pdf.services,
      mail: mail.services,
      screenAwake: awake,
    );
    final seed = await build();
    await seed<SettingsRepository>().save(
      (await seed<SettingsRepository>().load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        mailProvider: MailProviderId.gmail,
        senderAccount: testAccount,
        scanFlowMode: flowMode,
      ),
    );
    await tester.pumpWidget(OneClickScanApp(container: await build()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeKeys.scanAndSend));
    await tester.pumpAndSettle();
    if (capture) {
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pumpAndSettle();
    }
  }

  Future<void> shoot(WidgetTester tester) async {
    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  testWidgets('the camera screen does not hold the screen on', (tester) async {
    await pumpScan(tester, flowMode: ScanFlowMode.oneClick, capture: false);

    expect(awake.isOn, isFalse);
    expect(awake.calls, isEmpty);
  });

  testWidgets('success: on while it works, off at the end', (tester) async {
    await pumpScan(tester, flowMode: ScanFlowMode.oneClick, capture: false);
    mail.sender.hold = Completer<MailOutcome>();

    await shoot(tester);
    expect(awake.isOn, isTrue, reason: 'the send is running');

    mail.sender.hold!.complete(const MailSent());
    await tester.pumpAndSettle();
    expect(
      find.text('The message was sent from the e-mail server.'),
      findsOneWidget,
    );
    expect(awake.isOn, isFalse);
    expect(awake.calls, [true, false], reason: 'one on, one off, nothing else');
  });

  testWidgets('a mail error: off, and a manual retry is on again, then off', (
    tester,
  ) async {
    await pumpScan(tester, flowMode: ScanFlowMode.oneClick, capture: false);
    mail.sender.outcome = const MailNetworkError();
    await shoot(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(ScanKeys.mailRetry), findsOneWidget);
    expect(awake.isOn, isFalse);

    mail.sender.hold = Completer<MailOutcome>();
    await tapKeyNoSettle(tester, ScanKeys.mailRetry);
    expect(awake.isOn, isTrue);
    mail.sender.hold!.complete(const MailNetworkError());
    await tester.pumpAndSettle();
    expect(awake.isOn, isFalse);
  });

  testWidgets('a PDF that fails: off', (tester) async {
    await pumpScan(tester, flowMode: ScanFlowMode.oneClick, capture: false);
    pdf.builder.failWith = const ScanPdfException(ScanPdfFailure.buildFailed);

    await shoot(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(ScanKeys.pdfFailure), findsOneWidget);
    expect(awake.isOn, isFalse);
  });

  testWidgets('Cancel while sending: off', (tester) async {
    await pumpScan(tester, flowMode: ScanFlowMode.oneClick, capture: false);
    mail.sender.hold = Completer<MailOutcome>();
    await shoot(tester);
    expect(awake.isOn, isTrue);

    await tester.tap(find.byKey(ScanKeys.flowCancel));
    await tester.pumpAndSettle();

    expect(awake.isOn, isFalse);
  });

  testWidgets('Cancel while reading: off', (tester) async {
    await pumpScan(tester, flowMode: ScanFlowMode.oneClick, capture: false);
    rig.engine.gate = Completer<void>();
    await shoot(tester);
    expect(awake.isOn, isTrue);

    await tester.tap(find.byKey(ScanKeys.flowCancel));
    await tester.pumpAndSettle();

    expect(awake.isOn, isFalse);
  });

  testWidgets('the preview waits for the user with the screen free; Send '
      'holds it only while it sends', (tester) async {
    await pumpScan(tester, flowMode: ScanFlowMode.preview);
    expect(find.byKey(ScanKeys.mailSend), findsOneWidget);
    expect(awake.isOn, isFalse, reason: 'nothing runs in the preview');

    mail.sender.hold = Completer<MailOutcome>();
    await tapKeyNoSettle(tester, ScanKeys.mailSend);
    expect(awake.isOn, isTrue);

    mail.sender.hold!.complete(const MailSent());
    await tester.pumpAndSettle();
    expect(awake.isOn, isFalse);
  });

  testWidgets('Discard: off when it is done', (tester) async {
    await pumpScan(tester, flowMode: ScanFlowMode.preview);

    await tapKey(tester, ScanKeys.discard);
    await tapKey(tester, ScanKeys.discardConfirm);

    expect(find.text('The scan was deleted.'), findsOneWidget);
    expect(awake.isOn, isFalse);
  });

  testWidgets('leaving the screen while it works (the widget goes away) '
      'switches it off', (tester) async {
    await pumpScan(tester, flowMode: ScanFlowMode.oneClick, capture: false);
    rig.engine.gate = Completer<void>();
    await shoot(tester);
    expect(awake.isOn, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));

    expect(awake.isOn, isFalse);
  });
}

Future<void> tapKeyNoSettle(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pump(const Duration(milliseconds: 200));
}
