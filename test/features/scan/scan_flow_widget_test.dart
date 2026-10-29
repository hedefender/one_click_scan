import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// The whole flow on the screen with real cubits and fake adapters: One Click
/// and the preview with Send / Discard (ADR-025 to ADR-027).
void main() {
  late OcrTestRig rig;
  late PdfTestRig pdf;
  late MailTestRig mail;
  late FakeScanFileStore store;
  late FakeGalleryService gallery;

  const pdfUri =
      'content://com.example.test/tree/Scans/document/pdf%2F2026-10-21_19-05-12.pdf';

  Future<void> pumpScan(
    WidgetTester tester, {
    ScanFlowMode? flowMode,
    MailSendMode sendMode = MailSendMode.sendNow,
    bool withPassword = true,
    bool toGallery = true,
    bool capture = true,
  }) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    rig = OcrTestRig();
    pdf = PdfTestRig();
    mail = MailTestRig();
    if (withPassword) mail.storePassword();
    store = FakeScanFileStore();
    gallery = FakeGalleryService();
    final values = InMemoryKeyValueStore();
    Future<GetIt> build() => buildTestContainer(
      store: values,
      scanFileStore: store,
      gallery: gallery,
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
        saveToGallery: toGallery,
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

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  group('preview', () {
    testWidgets('shows the pages with Send and Discard; sends nothing yet', (
      tester,
    ) async {
      await pumpScan(tester, flowMode: ScanFlowMode.preview);

      expect(find.text('Check the scan'), findsOneWidget);
      expect(find.byKey(ScanKeys.mailSend), findsOneWidget);
      expect(find.byKey(ScanKeys.discard), findsOneWidget);
      expect(find.byKey(ScanKeys.pdfOpen), findsOneWidget);
      expect(
        find.byKey(ScanKeys.resultFile('2026-10-21_19-05-12_1.jpg')),
        findsOneWidget,
      );
      expect(mail.sender.sent, isEmpty);
      expect(store.files('pdf'), ['2026-10-21_19-05-12.pdf']);
    });

    testWidgets('an install without a choice behaves as the preview', (
      tester,
    ) async {
      await pumpScan(tester, flowMode: null);

      expect(find.byKey(ScanKeys.discard), findsOneWidget);
      expect(find.byKey(ScanKeys.mailSend), findsOneWidget);
      expect(mail.sender.sent, isEmpty);
    });

    testWidgets('Send sends the message', (tester) async {
      await pumpScan(tester, flowMode: ScanFlowMode.preview);

      await tapKey(tester, ScanKeys.mailSend);

      expect(mail.sender.sent, hasLength(1));
      expect(
        find.text('The message was sent from the e-mail server.'),
        findsOneWidget,
      );
      expect(find.byKey(ScanKeys.discard), findsNothing);
    });

    testWidgets('Send in the share mode opens the e-mail app', (tester) async {
      await pumpScan(
        tester,
        flowMode: ScanFlowMode.preview,
        sendMode: MailSendMode.shareDraft,
      );

      await tapKey(tester, ScanKeys.mailSend);

      expect(mail.sharer.shared, hasLength(1));
      expect(mail.sender.sent, isEmpty);
    });

    testWidgets('Discard asks first; "Keep it" deletes nothing', (
      tester,
    ) async {
      await pumpScan(tester, flowMode: ScanFlowMode.preview);

      await tapKey(tester, ScanKeys.discard);
      expect(find.text('Delete this scan?'), findsOneWidget);
      await tester.tap(find.byKey(ScanKeys.discardKeep));
      await tester.pumpAndSettle();

      expect(store.deletedUris, isEmpty);
      expect(gallery.deletedUris, isEmpty);
      expect(store.files('pdf'), hasLength(1));
      expect(store.files('pictures'), hasLength(1));
      expect(find.byKey(ScanKeys.discard), findsOneWidget);
      expect(find.text('The scan was deleted.'), findsNothing);
    });

    testWidgets('Discard deletes the pictures, the PDF and the Gallery copy', (
      tester,
    ) async {
      await pumpScan(tester, flowMode: ScanFlowMode.preview);

      await tapKey(tester, ScanKeys.discard);
      await tapKey(tester, ScanKeys.discardConfirm);

      expect(find.text('The scan was deleted.'), findsOneWidget);
      expect(store.files('pictures'), isEmpty);
      expect(store.files('pdf'), isEmpty);
      expect(gallery.deletedUris, hasLength(1));
      expect(mail.sender.sent, isEmpty);
      expect(find.byKey(ScanKeys.mailSend), findsNothing);
      expect(find.byKey(ScanKeys.pdfOpen), findsNothing);
    });

    testWidgets('a deletion that fails in part is not called done', (
      tester,
    ) async {
      await pumpScan(tester, flowMode: ScanFlowMode.preview);
      store.failDeleteUris.add(pdfUri);

      await tapKey(tester, ScanKeys.discard);
      await tapKey(tester, ScanKeys.discardConfirm);

      expect(find.text('The scan was deleted.'), findsNothing);
      expect(
        find.text('Not everything was deleted. Still there: the PDF.'),
        findsOneWidget,
      );
      expect(store.files('pictures'), isEmpty);
      expect(store.files('pdf'), hasLength(1));
      // It can be tried again.
      store.failDeleteUris.clear();
      await tapKey(tester, ScanKeys.discard);
      await tapKey(tester, ScanKeys.discardConfirm);
      expect(find.text('The scan was deleted.'), findsOneWidget);
      expect(store.files('pdf'), isEmpty);
    });
  });

  group('One Click', () {
    testWidgets('one tap: stored, read, PDF, sent; no preview', (tester) async {
      await pumpScan(tester, flowMode: ScanFlowMode.oneClick);

      expect(
        find.text('The message was sent from the e-mail server.'),
        findsOneWidget,
      );
      expect(mail.sender.sent, hasLength(1));
      expect(store.files('pictures'), hasLength(1));
      expect(store.files('pdf'), hasLength(1));
      expect(gallery.saved, hasLength(1));
      expect(find.byKey(ScanKeys.discard), findsNothing);
      expect(find.byKey(ScanKeys.mailSend), findsNothing);
      expect(find.text('Check the scan'), findsNothing);
    });

    testWidgets('no internet: "Not sent", the scan is kept, retry works', (
      tester,
    ) async {
      await pumpScan(tester, flowMode: ScanFlowMode.oneClick, capture: false);
      mail.sender.outcome = const MailNetworkError();
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pumpAndSettle();

      expect(find.byKey(ScanKeys.flowNotSent), findsOneWidget);
      expect(find.text('Not sent'), findsOneWidget);
      expect(
        find.text(
          'Could not connect to the e-mail server. Check the internet and try '
          'again.',
        ),
        findsOneWidget,
      );
      expect(store.files('pdf'), hasLength(1));
      expect(store.files('pictures'), hasLength(1));
      expect(mail.sender.sent, hasLength(1));

      mail.sender.outcome = const MailSent();
      await tapKey(tester, ScanKeys.mailRetry);

      expect(mail.sender.sent, hasLength(2)); // by hand, never by itself
      expect(
        find.text('The message was sent from the e-mail server.'),
        findsOneWidget,
      );
    });

    testWidgets('nothing is retried in the background', (tester) async {
      await pumpScan(tester, flowMode: ScanFlowMode.oneClick, capture: false);
      mail.sender.outcome = const MailNetworkError();
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 5));
      await tester.pumpAndSettle();

      expect(mail.sender.sent, hasLength(1));
    });

    testWidgets('no app password: stored, not sent, the way to Settings', (
      tester,
    ) async {
      await pumpScan(
        tester,
        flowMode: ScanFlowMode.oneClick,
        withPassword: false,
      );

      expect(find.text('Not sent'), findsOneWidget);
      expect(find.byKey(ScanKeys.mailOpenSettings), findsOneWidget);
      expect(store.files('pdf'), hasLength(1));
      expect(store.files('pictures'), hasLength(1));
      expect(mail.sender.sent, isEmpty);
    });

    testWidgets('the share mode opens the e-mail app at once', (tester) async {
      await pumpScan(
        tester,
        flowMode: ScanFlowMode.oneClick,
        sendMode: MailSendMode.shareDraft,
      );

      expect(mail.sharer.shared, hasLength(1));
      expect(mail.sender.sent, isEmpty);
      expect(find.byKey(ScanKeys.mailDraft), findsOneWidget);
    });

    testWidgets('Multi page: one tap on "Done" finishes the whole flow', (
      tester,
    ) async {
      await pumpScan(tester, flowMode: ScanFlowMode.oneClick, capture: false);
      await tester.tap(find.text('Multi page'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pumpAndSettle();
      expect(mail.sender.sent, isEmpty); // the scan goes on, page by page

      await tester.tap(find.byKey(ScanKeys.done));
      await tester.pumpAndSettle();

      expect(mail.sender.sent, hasLength(1));
      expect(store.files('pictures'), hasLength(2));
      expect(pdf.builder.builds.single, hasLength(2));
    });

    testWidgets('Cancel while sending: nothing is sent, the scan is kept', (
      tester,
    ) async {
      await pumpScan(tester, flowMode: ScanFlowMode.oneClick, capture: false);
      mail.sender.hold = Completer<MailOutcome>();
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(ScanKeys.flowStatus), findsOneWidget);
      expect(find.text('Sending…'), findsWidgets);
      final back = tester.widget<FilledButton>(find.byKey(ScanKeys.resultBack));
      expect(back.onPressed, isNull); // leaving is locked
      await tester.tap(find.byKey(ScanKeys.flowCancel));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Cancelled. The scan and the PDF are saved. Nothing was sent.',
        ),
        findsOneWidget,
      );
      expect(store.files('pdf'), hasLength(1));
      // The user can still send by hand.
      expect(find.byKey(ScanKeys.mailSend), findsOneWidget);
    });

    testWidgets('Cancel while reading: pictures stay, no PDF', (tester) async {
      await pumpScan(tester, flowMode: ScanFlowMode.oneClick, capture: false);
      rig.engine.gate = Completer<void>();
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(ScanKeys.flowCancel), findsOneWidget);
      await tester.tap(find.byKey(ScanKeys.flowCancel));
      await tester.pumpAndSettle();

      expect(
        find.text('Processing stopped. The photos are saved, no PDF was made.'),
        findsOneWidget,
      );
      expect(store.files('pictures'), hasLength(1));
      expect(store.files('pdf'), isEmpty);
      expect(mail.sender.sent, isEmpty);
    });
  });

  /// The system Back button (the same path as the arrow of the app bar).
  Future<void> systemBack(WidgetTester tester) async {
    final message = const JSONMethodCodec().encodeMethodCall(
      const MethodCall('popRoute'),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      message,
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  group('Phase 5.1: Cancel in every stage, Back = Cancel', () {
    Future<void> startWithPdfHeld(WidgetTester tester) async {
      await pumpScan(tester, flowMode: ScanFlowMode.oneClick, capture: false);
      pdf.builder.gate = Completer<void>();
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('while the PDF is made: Cancel stops at once, no PDF stays', (
      tester,
    ) async {
      await startWithPdfHeld(tester);

      expect(find.byKey(ScanKeys.pdfStatus), findsOneWidget);
      expect(find.byKey(ScanKeys.flowCancel), findsOneWidget);
      await tester.tap(find.byKey(ScanKeys.flowCancel));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Processing stopped. The photos are saved, no PDF was made.'),
        findsOneWidget,
      );
      pdf.builder.gate!.complete();
      await tester.pumpAndSettle();

      expect(store.files('pdf'), isEmpty);
      expect(store.files('pictures'), hasLength(1));
      expect(mail.sender.sent, isEmpty);
      expect(find.byKey(ScanKeys.mailSend), findsNothing);
      // One tap back home.
      await tester.tap(find.byKey(ScanKeys.resultBack));
      await tester.pumpAndSettle();
      expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);
    });

    testWidgets('the Back arrow asks, "Continue" changes nothing', (
      tester,
    ) async {
      await startWithPdfHeld(tester);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Stop the processing?'), findsOneWidget);
      await tester.tap(find.byKey(ScanKeys.stopContinue));
      await tester.pumpAndSettle();

      expect(find.text('Stop the processing?'), findsNothing);
      expect(find.byKey(ScanKeys.flowCancel), findsOneWidget);
      expect(find.byKey(ScanKeys.resultSummary), findsOneWidget);

      pdf.builder.gate!.complete();
      await tester.pumpAndSettle();
      expect(store.files('pdf'), hasLength(1)); // it went on
    });

    testWidgets('the system Back with "Stop" is the Cancel button', (
      tester,
    ) async {
      await startWithPdfHeld(tester);

      await systemBack(tester);
      expect(find.text('Stop the processing?'), findsOneWidget);
      await tester.tap(find.byKey(ScanKeys.stopConfirm));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Processing stopped. The photos are saved, no PDF was made.'),
        findsOneWidget,
      );
      pdf.builder.gate!.complete();
      await tester.pumpAndSettle();
      expect(store.files('pdf'), isEmpty);
      expect(find.byKey(ScanKeys.resultSummary), findsOneWidget); // not left
    });

    testWidgets('Back while reading asks and stops the reading', (
      tester,
    ) async {
      await pumpScan(tester, flowMode: ScanFlowMode.oneClick, capture: false);
      rig.engine.gate = Completer<void>();
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      await systemBack(tester);
      await tester.tap(find.byKey(ScanKeys.stopConfirm));
      await tester.pumpAndSettle();

      expect(store.files('pictures'), hasLength(1));
      expect(store.files('pdf'), isEmpty);
      expect(mail.sender.sent, isEmpty);
    });

    testWidgets('Back while sending asks and stops the send', (tester) async {
      await pumpScan(tester, flowMode: ScanFlowMode.oneClick, capture: false);
      mail.sender.hold = Completer<MailOutcome>();
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      await systemBack(tester);
      expect(find.text('Stop the processing?'), findsOneWidget);
      await tester.tap(find.byKey(ScanKeys.stopConfirm));
      await tester.pumpAndSettle();

      expect(store.files('pdf'), hasLength(1));
      expect(find.byKey(ScanKeys.flowCancelled), findsOneWidget);
    });

    testWidgets('when nothing runs, Back leaves without a question', (
      tester,
    ) async {
      await pumpScan(tester, flowMode: ScanFlowMode.preview);

      await systemBack(tester);

      expect(find.text('Stop the processing?'), findsNothing);
      expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);
    });
  });

  group('Phase 5.1: the screen after Discard', () {
    testWidgets('a complete discard leaves no preview text or button', (
      tester,
    ) async {
      await pumpScan(tester, flowMode: ScanFlowMode.preview);

      await tapKey(tester, ScanKeys.discard);
      await tapKey(tester, ScanKeys.discardConfirm);

      expect(find.text('The scan was deleted.'), findsOneWidget);
      expect(find.text('Check the scan'), findsNothing);
      expect(find.byKey(ScanKeys.flowStatus), findsNothing); // the hint
      expect(find.byKey(ScanKeys.mailSend), findsNothing);
      expect(find.byKey(ScanKeys.discard), findsNothing);
      expect(find.byKey(ScanKeys.flowCancel), findsNothing);
    });

    testWidgets('a partial discard says what is left; no hint, no Send', (
      tester,
    ) async {
      await pumpScan(tester, flowMode: ScanFlowMode.preview);
      store.failDeleteUris.add(pdfUri);

      await tapKey(tester, ScanKeys.discard);
      await tapKey(tester, ScanKeys.discardConfirm);

      expect(
        find.text('Not everything was deleted. Still there: the PDF.'),
        findsOneWidget,
      );
      expect(find.text('Check the scan'), findsNothing);
      expect(find.byKey(ScanKeys.flowStatus), findsNothing);
      expect(find.byKey(ScanKeys.mailSend), findsNothing);
    });
  });

  group('Phase 5.1: the automatic return', () {
    testWidgets('after a successful send it counts down and goes home', (
      tester,
    ) async {
      await pumpScan(tester, flowMode: ScanFlowMode.oneClick);

      expect(find.text('Back to home in 10 s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Back to home in 9 s'), findsOneWidget);

      await tester.pump(const Duration(seconds: 9));
      await tester.pumpAndSettle();

      expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);
      expect(find.byKey(ScanKeys.resultSummary), findsNothing);
    });

    testWidgets('any touch stops it; the manual button still works', (
      tester,
    ) async {
      await pumpScan(tester, flowMode: ScanFlowMode.oneClick);
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(find.byKey(ScanKeys.resultSummary));
      await tester.pump();
      expect(find.byKey(ScanKeys.autoReturn), findsNothing);
      await tester.pump(const Duration(seconds: 30));

      expect(find.byKey(ScanKeys.resultSummary), findsOneWidget);
      await tester.tap(find.byKey(ScanKeys.resultBack));
      await tester.pumpAndSettle();
      expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);
    });

    testWidgets('the preview counts after its Send, not before', (
      tester,
    ) async {
      await pumpScan(tester, flowMode: ScanFlowMode.preview);
      expect(find.byKey(ScanKeys.autoReturn), findsNothing);
      await tester.pump(const Duration(seconds: 15));
      expect(find.byKey(ScanKeys.resultSummary), findsOneWidget);

      await tapKey(tester, ScanKeys.mailSend);

      expect(find.text('Back to home in 10 s'), findsOneWidget);
    });

    testWidgets('no countdown when the message did not leave', (tester) async {
      await pumpScan(tester, flowMode: ScanFlowMode.oneClick, capture: false);
      mail.sender.outcome = const MailNetworkError();
      await tester.tap(find.byKey(ScanKeys.capture));
      await tester.pumpAndSettle();

      expect(find.byKey(ScanKeys.flowNotSent), findsOneWidget);
      expect(find.byKey(ScanKeys.autoReturn), findsNothing);
      await tester.pump(const Duration(seconds: 30));
      expect(find.byKey(ScanKeys.resultSummary), findsOneWidget);
    });

    testWidgets('no countdown when the e-mail app was opened', (tester) async {
      await pumpScan(
        tester,
        flowMode: ScanFlowMode.oneClick,
        sendMode: MailSendMode.shareDraft,
      );

      expect(find.byKey(ScanKeys.autoReturn), findsNothing);
      await tester.pump(const Duration(seconds: 30));
      expect(find.byKey(ScanKeys.resultSummary), findsOneWidget);
    });

    testWidgets('leaving early leaves no timer behind', (tester) async {
      await pumpScan(tester, flowMode: ScanFlowMode.oneClick);
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byKey(ScanKeys.resultBack));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 30));

      expect(find.byKey(HomeKeys.scanAndSend), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
