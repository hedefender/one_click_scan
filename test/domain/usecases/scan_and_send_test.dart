import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/core/errors/app_exceptions.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/entities/mail_send_mode.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';
import 'package:one_click_scan/domain/entities/scan_flow_mode.dart';
import 'package:one_click_scan/domain/entities/stored_scan.dart';
import 'package:one_click_scan/domain/mail/mail_outcome.dart';
import 'package:one_click_scan/domain/ports/draft_sharer.dart';
import 'package:one_click_scan/domain/repositories/settings_repository.dart';
import 'package:one_click_scan/domain/scan/scan_flow.dart';
import 'package:one_click_scan/domain/usecases/recognize_pages.dart';
import 'package:one_click_scan/domain/usecases/scan_and_send.dart';

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
  late SettingsRepository repository;
  late ScanAndSend flow;
  late OcrSession session;
  late ScanFlowCancellation cancellation;

  const scan = StoredScan(
    stem: '2026-10-21_19-05-12',
    pictures: [
      StoredPicture(
        fileName: '2026-10-21_19-05-12_1.jpg',
        sourcePath: 'cache/1.jpg',
      ),
    ],
  );

  Future<void> setUpRig({
    ScanFlowMode? flowMode,
    MailSendMode sendMode = MailSendMode.sendNow,
    bool password = true,
    int pages = 1,
  }) async {
    rig = OcrTestRig();
    pdf = PdfTestRig();
    mail = MailTestRig();
    if (password) mail.storePassword();
    store = FakeScanFileStore();
    final container = await buildTestContainer(
      scanFileStore: store,
      pdf: pdf.services,
      mail: mail.services,
    );
    repository = container<SettingsRepository>();
    await repository.save(
      (await repository.load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        mailProvider: MailProviderId.gmail,
        senderAccount: testAccount,
        mailSendMode: sendMode,
        scanFlowMode: flowMode,
      ),
    );
    flow = container<ScanAndSend>();
    cancellation = ScanFlowCancellation();
    session = rig.recognize.start(packId: 'greek');
    for (var i = 1; i <= pages; i++) {
      session.add('shot$i', 'cache/$i.jpg');
    }
    session.close();
  }

  /// The states of one run; the progress reports of the reading (several
  /// [FlowRecognizing]) count as one.
  Future<List<ScanFlowState>> run([OcrSession? override]) async {
    final all = await flow
        .run(
          scan: scan,
          session: override ?? session,
          cancellation: cancellation,
        )
        .toList();
    return [
      for (var i = 0; i < all.length; i++)
        if (!(all[i] is FlowRecognizing &&
            i > 0 &&
            all[i - 1] is FlowRecognizing))
          all[i],
    ];
  }

  tearDown(() => session.dispose());

  group('preview mode', () {
    test('stops at the decision: PDF stored, nothing sent', () async {
      await setUpRig(flowMode: ScanFlowMode.preview);

      final states = await run();

      expect(states.last, isA<FlowAwaitingDecision>());
      expect(states.whereType<FlowBuildingPdf>(), hasLength(1));
      expect(states.whereType<FlowSending>(), isEmpty);
      expect(store.files('pdf'), ['2026-10-21_19-05-12.pdf']);
      expect(mail.sender.sent, isEmpty);
      expect(mail.sharer.shared, isEmpty);
    });

    test('an install without a choice behaves as the preview', () async {
      await setUpRig(flowMode: null);

      final states = await run();

      expect(states.last, isA<FlowAwaitingDecision>());
      expect(mail.sender.sent, isEmpty);
    });
  });

  group('One Click', () {
    test('sends the PDF by SMTP: stages in order, one message', () async {
      await setUpRig(flowMode: ScanFlowMode.oneClick);

      final states = await run();

      expect(states.map((s) => s.runtimeType), [
        FlowRecognizing,
        FlowBuildingPdf,
        FlowSending,
        FlowFinished,
      ]);
      final done = states.last as FlowFinished;
      expect(done.delivery, isA<DeliverySent>());
      expect(mail.sender.sent, hasLength(1));
      expect(
        mail.sender.sent.single.subject,
        'One Click Scan - 2026-10-21_19-05-12',
      );
      expect(mail.sender.sent.single.attachments, hasLength(1));
      expect(store.files('pdf'), hasLength(1));
    });

    test('several pages: one PDF, one message', () async {
      await setUpRig(flowMode: ScanFlowMode.oneClick, pages: 3);

      final states = await run();

      final done = states.last as FlowFinished;
      expect(done.pdf.pageCount, 3);
      expect(mail.sender.sent, hasLength(1));
      expect(pdf.builder.builds.single, hasLength(3));
    });

    test('shareDraft: opens the e-mail app, sends nothing itself', () async {
      await setUpRig(
        flowMode: ScanFlowMode.oneClick,
        sendMode: MailSendMode.shareDraft,
      );

      final states = await run();

      expect(states.map((s) => s.runtimeType), [
        FlowRecognizing,
        FlowBuildingPdf,
        FlowSharing,
        FlowFinished,
      ]);
      final delivery = (states.last as FlowFinished).delivery;
      expect(delivery, isA<DeliveryShared>());
      expect((delivery as DeliveryShared).result, DraftShareResult.opened);
      expect(mail.sharer.shared, hasLength(1));
      expect(mail.sender.sent, isEmpty);
    });

    test(
      'no stored password: the scan is stored, the mail is not sent',
      () async {
        await setUpRig(flowMode: ScanFlowMode.oneClick, password: false);

        final states = await run();

        final done = states.last as FlowFinished;
        final delivery = done.delivery as DeliveryNotSent;
        expect(delivery.outcome, isA<MailNotConfigured>());
        expect(store.files('pdf'), [done.pdf.fileName]);
        expect(mail.sender.sent, isEmpty);
      },
    );

    test('incomplete account settings: stored, not sent', () async {
      await setUpRig(flowMode: ScanFlowMode.oneClick);
      await repository.save(
        (await repository.load()).copyWith(mailProvider: null),
      );

      final states = await run();

      final delivery =
          (states.last as FlowFinished).delivery as DeliveryNotSent;
      expect(delivery.outcome, isA<MailNotConfigured>());
      expect(store.files('pdf'), hasLength(1));
    });

    test('no network: not sent, the PDF stays, nothing is queued', () async {
      await setUpRig(flowMode: ScanFlowMode.oneClick);
      mail.sender.outcome = const MailNetworkError();

      final states = await run();

      final delivery =
          (states.last as FlowFinished).delivery as DeliveryNotSent;
      expect(delivery.outcome, isA<MailNetworkError>());
      expect(store.files('pdf'), hasLength(1));
      expect(mail.sender.sent, hasLength(1)); // one attempt, no automatic retry
    });

    test('a sender that throws is a failed mail, not a lost scan', () async {
      await setUpRig(flowMode: ScanFlowMode.oneClick);
      mail.sender.throwOnSend = StateError('boom');

      final states = await run();

      final delivery =
          (states.last as FlowFinished).delivery as DeliveryNotSent;
      expect(delivery.outcome, isA<MailUnknown>());
      expect(store.files('pdf'), hasLength(1));
    });

    test('a sharer that throws is a failed mail, not a lost scan', () async {
      await setUpRig(
        flowMode: ScanFlowMode.oneClick,
        sendMode: MailSendMode.shareDraft,
      );
      mail.appFinder.throws = true;

      final states = await run();

      // The finder failing is the share result `failed`, not an exception.
      final delivery = (states.last as FlowFinished).delivery as DeliveryShared;
      expect(delivery.result, DraftShareResult.failed);
      expect(store.files('pdf'), hasLength(1));
    });
  });

  group('the PDF', () {
    test('a timed out page still goes in, without text', () async {
      await setUpRig(flowMode: ScanFlowMode.preview);
      rig.engine.respond = (_) => const OcrTimedOut(Duration(seconds: 45));

      final states = await run();

      final decision = states.last as FlowAwaitingDecision;
      expect(decision.pdf.pageCount, 1);
      expect(decision.pdf.textPageCount, 0);
    });

    test('an OCR failure still makes the PDF and the flow goes on', () async {
      await setUpRig(flowMode: ScanFlowMode.oneClick);
      rig.engine.respond = (_) => const OcrFailed(OcrFailureReason.engineError);

      final states = await run();

      expect(states.last, isA<FlowFinished>());
      expect(mail.sender.sent, hasLength(1));
    });

    test('the writer fails: PdfFailed, nothing is sent', () async {
      await setUpRig(flowMode: ScanFlowMode.oneClick);
      pdf.builder.failWith = const ScanPdfException(ScanPdfFailure.buildFailed);

      final states = await run();

      expect(
        (states.last as FlowPdfFailed).failure,
        ScanPdfFailure.buildFailed,
      );
      expect(mail.sender.sent, isEmpty);
    });

    test('no folder in the settings: noAccess, nothing is built', () async {
      await setUpRig(flowMode: ScanFlowMode.oneClick);
      await repository.save(
        (await repository.load()).copyWith(storageFolder: null),
      );

      final states = await run();

      expect((states.last as FlowPdfFailed).failure, ScanPdfFailure.noAccess);
      expect(pdf.builder.builds, isEmpty);
    });

    test('no session at all: PdfFailed, not a crash', () async {
      await setUpRig(flowMode: ScanFlowMode.oneClick);

      final states = await flow
          .run(scan: scan, session: null, cancellation: cancellation)
          .toList();

      expect(
        (states.single as FlowPdfFailed).failure,
        ScanPdfFailure.pageImageMissing,
      );
    });

    test('a failed PDF can be run again: the readings are kept', () async {
      await setUpRig(flowMode: ScanFlowMode.preview);
      store.failSubfolder = 'pdf';
      expect(await run(), [
        isA<FlowRecognizing>(),
        isA<FlowBuildingPdf>(),
        isA<FlowPdfFailed>(),
      ]);

      store.failSubfolder = null;
      final again = await run();

      expect(again.last, isA<FlowAwaitingDecision>());
      expect(rig.engine.recognized, hasLength(1)); // read once
    });
  });

  group('cancel', () {
    test('while reading: pictures stay, no PDF is made', () async {
      await setUpRig(flowMode: ScanFlowMode.oneClick);
      rig.engine.gate = Completer<void>();
      final states = <ScanFlowState>[];
      final done = flow
          .run(scan: scan, session: session, cancellation: cancellation)
          .forEach(states.add);
      await pumpEventQueue();

      cancellation.cancel();
      rig.engine.gate!.complete();
      await done;

      expect((states.last as FlowCancelled).stage, ScanFlowStage.recognizing);
      expect(pdf.builder.builds, isEmpty);
      expect(store.files('pdf'), isEmpty);
      expect(mail.sender.sent, isEmpty);
    });

    test('while sending: the PDF is stored, the send is stopped', () async {
      await setUpRig(flowMode: ScanFlowMode.oneClick);
      mail.sender.hold = Completer<MailOutcome>();
      final states = <ScanFlowState>[];
      final done = flow
          .run(scan: scan, session: session, cancellation: cancellation)
          .forEach(states.add);
      await pumpEventQueue();
      expect(states.last, isA<FlowSending>());

      cancellation.cancel();
      await done;

      final cancelled = states.last as FlowCancelled;
      expect(cancelled.stage, ScanFlowStage.sending);
      expect(cancelled.pdf, isNotNull);
      expect(store.files('pdf'), hasLength(1));
    });

    test('cancelled before the delivery: nothing is sent', () async {
      await setUpRig(flowMode: ScanFlowMode.oneClick);
      cancellation.cancel();

      final states = await run();

      expect(states.last, isA<FlowCancelled>());
      expect(mail.sender.sent, isEmpty);
    });
  });

  test('logs no content of the scan or of the mail', () async {
    final logger = CapturingLogger();
    rig = OcrTestRig();
    pdf = PdfTestRig();
    mail = MailTestRig()..storePassword();
    store = FakeScanFileStore();
    final container = await buildTestContainer(
      scanFileStore: store,
      pdf: pdf.services,
      mail: mail.services,
      logger: logger,
    );
    repository = container<SettingsRepository>();
    await repository.save(
      (await repository.load()).copyWith(
        firstRunCompleted: true,
        storageFolder: testFolder,
        mailProvider: MailProviderId.gmail,
        senderAccount: testAccount,
        scanFlowMode: ScanFlowMode.oneClick,
      ),
    );
    mail.sender.throwOnSend = StateError(canarySecret);
    session = rig.recognize.start(packId: 'greek')
      ..add('shot1', 'cache/1.jpg')
      ..close();

    await container<ScanAndSend>()
        .run(scan: scan, session: session, cancellation: ScanFlowCancellation())
        .toList();

    expect(logger.all, isNot(contains(canarySecret)));
    expect(logger.all, isNot(contains(testAccount)));
  });
}
