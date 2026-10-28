import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';
import 'package:one_click_scan/domain/entities/scan_flow_mode.dart';
import 'package:one_click_scan/domain/entities/stored_scan.dart';
import 'package:one_click_scan/domain/mail/mail_outcome.dart';
import 'package:one_click_scan/domain/ports/open_pdf.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/domain/scan/scan_flow.dart';
import 'package:one_click_scan/domain/usecases/discard_scan.dart';
import 'package:one_click_scan/domain/usecases/load_settings.dart';
import 'package:one_click_scan/domain/usecases/recognize_pages.dart';
import 'package:one_click_scan/domain/usecases/scan_and_send.dart';
import 'package:one_click_scan/features/scan/scan_flow_cubit.dart';

import '../../support/fakes.dart';
import '../../support/mail_fakes.dart';
import '../../support/ocr_fakes.dart';
import '../../support/pdf_fakes.dart';
import '../../support/scan_fakes.dart';

void main() {
  late OcrTestRig rig;
  late PdfTestRig pdf;
  late MailTestRig mail;
  late FakeScanFileStore store;
  late FakeGalleryService gallery;
  late RecordingLogger logger;
  late SettingsRepository repository;
  late ScanFlowCubit cubit;
  late OcrSession session;
  late GetIt container;

  final scan = StoredScan(
    stem: '2026-10-21_19-05-12',
    pictures: [
      const StoredPicture(
        fileName: '2026-10-21_19-05-12_1.jpg',
        sourcePath: 'cache/1.jpg',
        uri: 'content://com.example.test/tree/Scans/document/pictures%2F2026-10-21_19-05-12_1.jpg',
        gallery: GalleryCopyStatus.saved,
        galleryUri: 'content://media/external/images/media/7',
      ),
    ],
  );

  ScanFlowCubit make(OcrSession? s) => ScanFlowCubit(
    scan: scan,
    session: s,
    loadSettings: container<LoadSettings>(),
    scanAndSend: container<ScanAndSend>(),
    discardScan: container<DiscardScan>(),
    openPdf: pdf.opener,
    logger: logger,
  );

  Future<void> setUpRig({
    ScanFlowMode? flowMode,
    int pages = 1,
    bool withFolder = true,
  }) async {
    rig = OcrTestRig();
    pdf = PdfTestRig();
    mail = MailTestRig()..storePassword();
    store = FakeScanFileStore()
      ..folders['pictures'] = ['2026-10-21_19-05-12_1.jpg'];
    gallery = FakeGalleryService();
    logger = RecordingLogger();
    container = await buildTestContainer(
      scanFileStore: store,
      gallery: gallery,
      logger: logger,
      pdf: pdf.services,
      mail: mail.services,
    );
    repository = container<SettingsRepository>();
    await repository.save(
      (await repository.load()).copyWith(
        firstRunCompleted: true,
        storageFolder: withFolder ? testFolder : null,
        mailProvider: MailProviderId.gmail,
        senderAccount: testAccount,
        scanFlowMode: flowMode,
      ),
    );
    session = rig.recognize.start(packId: 'greek');
    for (var i = 1; i <= pages; i++) {
      session.add('shot$i', 'cache/$i.jpg');
    }
    cubit = make(session);
  }

  Future<void> untilFinal() async {
    for (var i = 0; i < 200; i++) {
      if (cubit.state.flow?.isFinal ?? false) return;
      await pumpEventQueue();
    }
    fail('the flow did not end: ${cubit.state.flow}');
  }

  tearDown(() async {
    await cubit.close();
    await session.dispose();
  });

  group('preview', () {
    test('reads, makes the PDF and waits for the decision', () async {
      await setUpRig(flowMode: ScanFlowMode.preview);
      rig.engine.gate = Completer<void>();
      session.close();

      await cubit.start();
      await pumpEventQueue();
      expect(cubit.state.flow, isA<FlowRecognizing>());
      expect(cubit.state.busy, isTrue);
      expect(pdf.builder.builds, isEmpty);

      rig.engine.gate!.complete();
      await untilFinal();

      expect(cubit.state.flow, isA<FlowAwaitingDecision>());
      expect(cubit.state.previewMode, isTrue);
      expect(cubit.state.busy, isFalse);
      expect(cubit.state.pdf!.fileName, '2026-10-21_19-05-12.pdf');
      expect(store.files('pdf'), ['2026-10-21_19-05-12.pdf']);
      expect(mail.sender.sent, isEmpty);
    });

    test('progress: page k of n while the reading goes on', () async {
      await setUpRig(flowMode: ScanFlowMode.preview, pages: 3);
      rig.engine.gate = Completer<void>();

      await cubit.start();
      await pumpEventQueue();

      final flow = cubit.state.flow as FlowRecognizing;
      expect(flow.total, 3);
      expect(flow.read, 0);

      rig.engine.gate!.complete();
      session.close();
      await untilFinal();
    });

    test('skipText: the pages go in without text, the PDF is made', () async {
      await setUpRig(flowMode: ScanFlowMode.preview, pages: 2);
      rig.engine.gate = Completer<void>();
      await cubit.start();
      await pumpEventQueue();

      cubit.skipText();
      session.close();
      await untilFinal();

      expect(cubit.state.pdf!.pageCount, 2);
      expect(cubit.state.pdf!.textPageCount, 0);
    });

    test('the working copies are deleted once the PDF is stored', () async {
      await setUpRig(flowMode: ScanFlowMode.preview, pages: 2);
      session.close();

      await cubit.start();
      await untilFinal();

      expect(rig.workStore.files, isEmpty);
      expect(pdf.builder.discarded, hasLength(1));
    });
  });

  group('an install from before Phase 5 (no choice stored)', () {
    test('shows the preview, and nothing is sent', () async {
      await setUpRig(flowMode: null);
      session.close();

      await cubit.start();
      await untilFinal();

      expect(cubit.state.previewMode, isTrue);
      expect(cubit.state.flow, isA<FlowAwaitingDecision>());
      expect(mail.sender.sent, isEmpty);
    });
  });

  group('One Click', () {
    test('goes on to the delivery with no decision', () async {
      await setUpRig(flowMode: ScanFlowMode.oneClick);
      session.close();

      await cubit.start();
      await untilFinal();

      expect(cubit.state.previewMode, isFalse);
      final done = cubit.state.flow as FlowFinished;
      expect(done.delivery, isA<DeliverySent>());
      expect(cubit.state.canDiscard, isFalse); // already sent
      expect(mail.sender.sent, hasLength(1));
    });

    test('cancel while sending: the PDF is kept, nothing is sent', () async {
      await setUpRig(flowMode: ScanFlowMode.oneClick);
      session.close();
      mail.sender.hold = Completer<MailOutcome>();
      await cubit.start();
      for (var i = 0; i < 100 && cubit.state.flow is! FlowSending; i++) {
        await pumpEventQueue();
      }
      expect(cubit.state.canCancel, isTrue);

      cubit.cancel();
      await untilFinal();

      final cancelled = cubit.state.flow as FlowCancelled;
      expect(cancelled.stage, ScanFlowStage.sending);
      expect(cubit.state.pdf, isNotNull);
      expect(store.files('pdf'), hasLength(1));
    });
  });

  group('cancel while reading', () {
    test('the pictures stay, no PDF is made', () async {
      await setUpRig(flowMode: ScanFlowMode.oneClick);
      rig.engine.gate = Completer<void>();
      session.close();
      await cubit.start();
      await pumpEventQueue();
      expect(cubit.state.canCancel, isTrue);

      cubit.cancel();
      await untilFinal();

      expect(cubit.state.flow, isA<FlowCancelled>());
      expect(pdf.builder.builds, isEmpty);
      expect(store.files('pictures'), isNotEmpty);
    });

    test('there is no cancel while the PDF is written or after it', () async {
      await setUpRig(flowMode: ScanFlowMode.preview);
      session.close();
      await cubit.start();
      await untilFinal();

      cubit.cancel(); // does nothing

      expect(cubit.state.flow, isA<FlowAwaitingDecision>());
      expect(cubit.state.canCancel, isFalse);
    });
  });

  group('failures: the photos stay, nothing crashes', () {
    test('the writer fails; retry makes the PDF', () async {
      await setUpRig(flowMode: ScanFlowMode.preview);
      session.close();
      store.failSubfolder = 'pdf';

      await cubit.start();
      await untilFinal();

      expect(cubit.state.flow, isA<FlowPdfFailed>());
      expect(cubit.state.busy, isFalse);
      expect(rig.workStore.files, isNotEmpty); // kept for the retry

      store.failSubfolder = null;
      await cubit.retry();
      await untilFinal();

      expect(cubit.state.flow, isA<FlowAwaitingDecision>());
      expect(store.files('pdf'), ['2026-10-21_19-05-12.pdf']);
      expect(rig.workStore.files, isEmpty);
    });

    test('retry does nothing unless the last attempt failed', () async {
      await setUpRig(flowMode: ScanFlowMode.preview);
      session.close();
      await cubit.start();
      await untilFinal();

      await cubit.retry();

      expect(pdf.builder.builds, hasLength(1));
    });

    test('no reading session: failed, not a crash', () async {
      await setUpRig(flowMode: ScanFlowMode.preview);
      await cubit.close();
      cubit = make(null);

      await cubit.start();
      await untilFinal();

      expect(cubit.state.flow, isA<FlowPdfFailed>());
    });
  });

  group('open the PDF', () {
    test('hands the URI to the viewer; a problem is a state', () async {
      await setUpRig(flowMode: ScanFlowMode.preview);
      session.close();
      await cubit.start();
      await untilFinal();

      await cubit.openPdf();
      expect(pdf.opener.opened, [cubit.state.pdf!.uri]);
      expect(cubit.state.openProblem, isNull);

      pdf.opener.result = OpenPdfResult.noViewer;
      await cubit.openPdf();
      expect(cubit.state.openProblem, OpenPdfResult.noViewer);

      pdf.opener.result = OpenPdfResult.opened;
      await cubit.openPdf();
      expect(cubit.state.openProblem, isNull);
    });

    test('nothing to open before the PDF exists', () async {
      await setUpRig(flowMode: ScanFlowMode.preview);
      rig.engine.gate = Completer<void>();
      await cubit.start();
      await pumpEventQueue();

      await cubit.openPdf();

      expect(pdf.opener.opened, isEmpty);
      rig.engine.gate!.complete();
      session.close();
      await untilFinal();
    });
  });

  group('discard (preview)', () {
    Future<void> reachDecision() async {
      session.close();
      await cubit.start();
      await untilFinal();
    }

    test('deletes the pictures, the PDF and the Gallery copy', () async {
      await setUpRig(flowMode: ScanFlowMode.preview);
      await reachDecision();
      expect(cubit.state.canDiscard, isTrue);

      await cubit.discard();

      expect(cubit.state.discarded, isTrue);
      expect(cubit.state.discardOutcome!.complete, isTrue);
      expect(store.files('pictures'), isEmpty);
      expect(store.files('pdf'), isEmpty);
      expect(gallery.deletedUris, ['content://media/external/images/media/7']);
      expect(mail.sender.sent, isEmpty);
      expect(cubit.state.pdfStored, isFalse);
    });

    test('a failure leaves the rest and never says "discarded"', () async {
      await setUpRig(flowMode: ScanFlowMode.preview);
      await reachDecision();
      gallery.failDeleteUris.add('content://media/external/images/media/7');

      await cubit.discard();

      expect(cubit.state.discarded, isFalse);
      expect(cubit.state.discardOutcome!.galleryLeft, 1);
      expect(cubit.state.discardOutcome!.picturesLeft, 0);
      expect(cubit.state.discardOutcome!.pdfLeft, isFalse);
      // A second try is allowed and finishes the job.
      expect(cubit.state.canDiscard, isTrue);
      gallery.failDeleteUris.clear();
      await cubit.discard();
      expect(cubit.state.discarded, isTrue);
    });

    test('is not offered in One Click, and not before the PDF', () async {
      await setUpRig(flowMode: ScanFlowMode.oneClick);
      session.close();
      rig.engine.gate = Completer<void>();
      await cubit.start();
      await pumpEventQueue();
      expect(cubit.state.canDiscard, isFalse);
      rig.engine.gate!.complete();
      await untilFinal();
      expect(cubit.state.canDiscard, isFalse);

      await cubit.discard(); // does nothing

      expect(store.deletedUris, isEmpty);
    });

    test('a mail that did not leave can still be discarded', () async {
      await setUpRig(flowMode: ScanFlowMode.preview);
      await reachDecision();
      expect(cubit.state.canDiscard, isTrue);
    });
  });

  test('closing the cubit while it waits does not crash', () async {
    await setUpRig(flowMode: ScanFlowMode.preview);
    rig.engine.gate = Completer<void>();
    await cubit.start();
    await pumpEventQueue();

    await cubit.close();
    rig.engine.gate!.complete();
    await pumpEventQueue();
  });

  test('a timed out page: the PDF is still made', () async {
    await setUpRig(flowMode: ScanFlowMode.preview);
    rig.engine.respond = (_) => const OcrTimedOut(Duration(seconds: 45));
    session.close();

    await cubit.start();
    await untilFinal();

    expect(cubit.state.pdf!.textPageCount, 0);
  });
}
