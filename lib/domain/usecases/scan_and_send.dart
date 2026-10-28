import 'dart:async';

import '../../core/errors/app_exceptions.dart';
import '../../core/logging/app_logger.dart';
import '../entities/app_settings.dart';
import '../entities/mail_send_mode.dart';
import '../entities/pdf_page_input.dart';
import '../entities/scan_flow_mode.dart';
import '../entities/stored_scan.dart';
import '../mail/mail_outcome.dart';
import '../scan/scan_flow.dart';
import 'load_settings.dart';
import 'recognize_pages.dart';
import 'send_scan_pdf.dart';
import 'store_scan_pdf.dart';

/// The flow after the capture: the text of the pages, the PDF, and the delivery
/// by the mode of Settings (`sendNow` or `shareDraft`), reported as a stream of
/// [ScanFlowState] (ADR-025).
///
/// The pictures are stored before this runs, and nothing here deletes them. A
/// failure of the PDF or of the mail is a state: the scan is never lost
/// because of a mail problem. In the preview mode the stream stops at
/// [FlowAwaitingDecision]; the user's "Send" and every "try again" of a mail
/// are the manual send of `MailSendCubit`. In One Click the stream goes on to
/// the delivery. Never throws.
class ScanAndSend {
  const ScanAndSend({
    required this.loadSettings,
    required this.storePdf,
    required this.send,
    required this.share,
    required this.logger,
  });

  final LoadSettings loadSettings;
  final StoreScanPdf storePdf;
  final SendScanPdf send;
  final ShareScanPdfDraft share;
  final AppLogger logger;

  /// From the stored pictures to the delivery (One Click) or to the decision
  /// (preview). Also the "try again" of a failed PDF: the readings stay in the
  /// [session], so a second run only repeats the PDF.
  Stream<ScanFlowState> run({
    required StoredScan scan,
    required OcrSession? session,
    required ScanFlowCancellation cancellation,
  }) {
    final controller = StreamController<ScanFlowState>();
    unawaited(_run(scan, session, cancellation, controller));
    return controller.stream;
  }

  Future<void> _run(
    StoredScan scan,
    OcrSession? session,
    ScanFlowCancellation cancellation,
    StreamController<ScanFlowState> out,
  ) async {
    try {
      if (session == null) {
        // No reading was started, so there is no picture to put in the PDF.
        out.add(const FlowPdfFailed(ScanPdfFailure.pageImageMissing));
        return;
      }
      final done = await _waitForText(session, cancellation, out);
      if (cancellation.isCancelled) {
        out.add(const FlowCancelled(ScanFlowStage.recognizing));
        return;
      }
      out.add(const FlowBuildingPdf());
      final StoredPdf pdf;
      try {
        pdf = await _makePdf(scan, session, done);
      } on ScanPdfException catch (error) {
        out.add(FlowPdfFailed(error.failure));
        return;
      } catch (error, stackTrace) {
        logger.error('Making the PDF failed unexpectedly', error, stackTrace);
        out.add(const FlowPdfFailed(ScanPdfFailure.buildFailed));
        return;
      }
      final settings = await loadSettings();
      if (settings.effectiveScanFlowMode == ScanFlowMode.preview) {
        out.add(FlowAwaitingDecision(pdf));
        return;
      }
      try {
        await _deliver(pdf, cancellation, out, settings);
      } catch (error, stackTrace) {
        // The PDF is stored: whatever failed here, the scan is not lost.
        logger.error(
          'Delivering failed unexpectedly',
          error.runtimeType,
          stackTrace,
        );
        out.add(
          FlowFinished(
            pdf: pdf,
            delivery: const DeliveryNotSent(MailUnknown()),
          ),
        );
      }
    } catch (error, stackTrace) {
      logger.error('The scan flow failed unexpectedly', error, stackTrace);
      out.add(const FlowPdfFailed(ScanPdfFailure.buildFailed));
    } finally {
      await out.close();
    }
  }

  Future<void> _deliver(
    StoredPdf pdf,
    ScanFlowCancellation cancellation,
    StreamController<ScanFlowState> out,
    AppSettings settings,
  ) async {
    if (cancellation.isCancelled) {
      out.add(FlowCancelled(ScanFlowStage.sending, pdf: pdf));
      return;
    }
    if (settings.mailSendMode == MailSendMode.shareDraft) {
      out.add(const FlowSharing());
      final result = await share(settings: settings, pdf: pdf);
      out.add(FlowFinished(pdf: pdf, delivery: DeliveryShared(result)));
      return;
    }
    out.add(const FlowSending());
    final MailOutcome outcome;
    try {
      outcome = await send(
        settings: settings,
        pdf: pdf,
        cancellation: cancellation.mail,
      );
    } catch (error, stackTrace) {
      // The use case promises an outcome; this is only a net under it.
      logger.error('Sending threw', error.runtimeType, stackTrace);
      out.add(
        FlowFinished(pdf: pdf, delivery: const DeliveryNotSent(MailUnknown())),
      );
      return;
    }
    out.add(switch (outcome) {
      MailSent() => FlowFinished(pdf: pdf, delivery: const DeliverySent()),
      MailCancelled() => FlowCancelled(ScanFlowStage.sending, pdf: pdf),
      _ => FlowFinished(pdf: pdf, delivery: DeliveryNotSent(outcome)),
    });
  }

  /// Waits until every page has an outcome, reporting the count. A cancel ends
  /// the reading at once.
  Future<OcrSessionSnapshot> _waitForText(
    OcrSession session,
    ScanFlowCancellation cancellation,
    StreamController<ScanFlowState> out,
  ) async {
    void report(OcrSessionSnapshot snapshot) {
      final read = snapshot.pages
          .where((p) => p.status == OcrPageStatus.done)
          .length;
      if (!out.isClosed) {
        out.add(FlowRecognizing(read: read, total: snapshot.pages.length));
      }
    }

    report(session.snapshot);
    final progress = session.snapshots.listen(report);
    unawaited(cancellation.whenCancelled.then((_) => session.cancel()));
    try {
      return await session.finished;
    } finally {
      // Not awaited: on a broadcast stream the future can wait for the session.
      unawaited(progress.cancel());
    }
  }

  Future<StoredPdf> _makePdf(
    StoredScan scan,
    OcrSession session,
    OcrSessionSnapshot done,
  ) async {
    final pages = <PdfPageInput>[];
    for (final page in done.pages) {
      final image = page.image;
      final outcome = page.outcome;
      if (image == null || outcome == null || page.workingCopyDeleted) {
        throw const ScanPdfException(ScanPdfFailure.pageImageMissing);
      }
      pages.add(PdfPageInput(image: image, outcome: outcome));
    }
    if (pages.isEmpty) {
      throw const ScanPdfException(ScanPdfFailure.pageImageMissing);
    }
    final folder = (await loadSettings()).storageFolder;
    if (folder == null) throw const ScanPdfException(ScanPdfFailure.noAccess);
    final stored = await storePdf(
      folder: folder,
      stem: scan.stem,
      pages: pages,
    );
    // The pictures are in the PDF now: no copy of them stays in the cache.
    await session.releaseWorkingCopies();
    return stored;
  }
}
