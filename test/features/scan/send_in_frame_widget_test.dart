import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:one_click_scan/app/app.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/mail_send_mode.dart';
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

/// Phase 6.7: "Send" of the preview is the primary button of the fixed frame
/// (with "OCR text (check)" and "Back to home"), so it is seen without
/// scrolling the list, on a small phone with big text, in both themes.
void main() {
  late OcrTestRig rig;
  late PdfTestRig pdf;
  late MailTestRig mail;

  Future<void> pumpScan(
    WidgetTester tester, {
    required Size dp,
    double textScale = 1.0,
    Brightness brightness = Brightness.light,
    MailSendMode sendMode = MailSendMode.sendNow,
    ScanFlowMode flowMode = ScanFlowMode.preview,
  }) async {
    tester.view.physicalSize = Size(dp.width * 3, dp.height * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    rig = OcrTestRig();
    pdf = PdfTestRig();
    mail = MailTestRig()..storePassword();
    final values = InMemoryKeyValueStore();
    Future<GetIt> build() => buildTestContainer(
      store: values,
      scanFileStore: FakeScanFileStore(),
      gallery: FakeGalleryService(),
      ocr: rig.services,
      pdf: pdf.services,
      mail: mail.services,
    );
    final seed = await build();
    await seed<SettingsRepository>().save(
      (await seed<SettingsRepository>().load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        mailProvider: MailProviderId.gmail,
        senderAccount: testAccount,
        mailSendMode: sendMode,
        scanFlowMode: flowMode,
      ),
    );
    await tester.pumpWidget(OneClickScanApp(container: await build()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeKeys.scanAndSend));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ScanKeys.capture));
    await tester.pumpAndSettle();
  }

  /// The list builds its rows as they come into view: scroll until [finder]
  /// exists.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(ScanKeys.resultList),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    // Fully in view, above the fixed frame.
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  final screens = <String, (Size, double)>{
    '360 x 640, text x1.3': (const Size(360, 640), 1.3),
    '411 x 914': (const Size(411, 914), 1.0),
  };

  for (final entry in screens.entries) {
    for (final brightness in Brightness.values) {
      testWidgets('Send is seen without scrolling: ${entry.key}, '
          '${brightness.name}', (tester) async {
        final (dp, scale) = entry.value;
        await pumpScan(
          tester,
          dp: dp,
          textScale: scale,
          brightness: brightness,
        );
        final send = find.byKey(ScanKeys.mailSend);

        expect(send, findsOneWidget);
        // Not in the list, and nothing covers it.
        expect(
          find.descendant(of: find.byKey(ScanKeys.resultList), matching: send),
          findsNothing,
        );
        expect(send.hitTestable(), findsOneWidget);
        expect(tester.getRect(send).bottom, lessThanOrEqualTo(dp.height));
        expect(tester.getRect(send).top, greaterThan(0));
        // The two other buttons of the frame are there and reachable too.
        expect(find.byKey(ScanKeys.resultOcr).hitTestable(), findsOneWidget);
        expect(find.byKey(ScanKeys.resultBack).hitTestable(), findsOneWidget);
        // Same size and shape as the other buttons (DESIGN_SPEC: height 56).
        expect(tester.getSize(send).height, 56);
        expect(tester.getSize(find.byKey(ScanKeys.resultBack)).height, 56);
        // The content stays reachable by scrolling above the frame.
        await tester.ensureVisible(find.byKey(ScanKeys.pdfOpen));
        await tester.pump();
        expect(find.byKey(ScanKeys.pdfOpen).hitTestable(), findsOneWidget);
        expect(send.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Send still sends, and then leaves the frame', (tester) async {
    await pumpScan(tester, dp: const Size(360, 640), textScale: 1.3);

    await tester.tap(find.byKey(ScanKeys.mailSend));
    await tester.pumpAndSettle();

    expect(mail.sender.sent, hasLength(1));
    await scrollTo(tester, find.byKey(ScanKeys.mailStatus));
    expect(
      find.text('The message was sent from the e-mail server.'),
      findsOneWidget,
    );
    expect(find.byKey(ScanKeys.mailSend), findsNothing);
    expect(find.byKey(ScanKeys.resultBack), findsOneWidget);
  });

  testWidgets('a failure keeps its text and buttons in the list; the frame '
      'has no Send then', (tester) async {
    await pumpScan(tester, dp: const Size(411, 914));
    mail.sender.outcome = const MailNetworkError();

    await tester.tap(find.byKey(ScanKeys.mailSend));
    await tester.pumpAndSettle();

    expect(find.byKey(ScanKeys.mailSend), findsNothing);
    await scrollTo(tester, find.byKey(ScanKeys.mailFailure));
    expect(find.byKey(ScanKeys.mailFailure), findsOneWidget);
    expect(find.byKey(ScanKeys.mailRetry), findsOneWidget);
    await scrollTo(tester, find.byKey(ScanKeys.mailOpenApp));
    expect(find.byKey(ScanKeys.mailOpenApp), findsOneWidget);
    // The retry is the manual send, as before.
    mail.sender.outcome = const MailSent();
    await scrollTo(tester, find.byKey(ScanKeys.mailRetry));
    await tester.tap(find.byKey(ScanKeys.mailRetry));
    await tester.pumpAndSettle();
    expect(mail.sender.sent, hasLength(2));
  });

  testWidgets('in the share mode the frame button opens the e-mail app', (
    tester,
  ) async {
    await pumpScan(
      tester,
      dp: const Size(360, 640),
      sendMode: MailSendMode.shareDraft,
    );

    expect(find.byKey(ScanKeys.mailSend).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(ScanKeys.mailSend));
    await tester.pumpAndSettle();

    expect(mail.sharer.shared, hasLength(1));
    expect(mail.sender.sent, isEmpty);
  });

  testWidgets('One Click is unchanged: no Send button, Back is the primary '
      'button', (tester) async {
    await pumpScan(
      tester,
      dp: const Size(360, 640),
      flowMode: ScanFlowMode.oneClick,
    );

    expect(mail.sender.sent, hasLength(1));
    expect(find.byKey(ScanKeys.mailSend), findsNothing);
    expect(find.byKey(ScanKeys.resultBack), findsOneWidget);
  });
}
