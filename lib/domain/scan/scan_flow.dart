import '../../core/errors/app_exceptions.dart';
import '../entities/pdf_page_input.dart';
import '../mail/mail_cancellation.dart';
import '../mail/mail_outcome.dart';
import '../ports/draft_sharer.dart';

/// The stage a flow was in when it was cancelled.
enum ScanFlowStage { recognizing, buildingPdf, sending }

/// How a finished scan left the phone (or why it did not).
sealed class ScanDelivery {
  const ScanDelivery();
}

/// The SMTP server accepted the message (nothing is known about delivery).
final class DeliverySent extends ScanDelivery {
  const DeliverySent();
}

/// The e-mail app was opened (or could not be). The user sends from there.
final class DeliveryShared extends ScanDelivery {
  const DeliveryShared(this.result);

  final DraftShareResult result;
}

/// The mail did not leave. The scan and the PDF are stored all the same.
final class DeliveryNotSent extends ScanDelivery {
  const DeliveryNotSent(this.outcome);

  final MailOutcome outcome;
}

/// What the flow after the capture reports, in order. The capture and the
/// storing of the pictures are the camera screen's own states
/// (`ScanPhase.capturing` / `saving`), before the flow starts.
sealed class ScanFlowState {
  const ScanFlowState();

  /// The flow has nothing more to say: the stream ends after this state.
  bool get isFinal => false;
}

/// Waiting for the text of the pages ([read] of [total] have an outcome).
final class FlowRecognizing extends ScanFlowState {
  const FlowRecognizing({required this.read, required this.total});

  final int read;
  final int total;
}

final class FlowBuildingPdf extends ScanFlowState {
  const FlowBuildingPdf();
}

/// Preview mode: the PDF is stored and the user decides (send or discard).
final class FlowAwaitingDecision extends ScanFlowState {
  const FlowAwaitingDecision(this.pdf);

  final StoredPdf pdf;

  @override
  bool get isFinal => true;
}

final class FlowSending extends ScanFlowState {
  const FlowSending();
}

/// The e-mail app is being opened (the `shareDraft` mode).
final class FlowSharing extends ScanFlowState {
  const FlowSharing();
}

/// The PDF is stored and the delivery step ended (well or not).
final class FlowFinished extends ScanFlowState {
  const FlowFinished({required this.pdf, required this.delivery});

  final StoredPdf pdf;
  final ScanDelivery delivery;

  @override
  bool get isFinal => true;
}

/// The pictures are stored but the PDF could not be made.
final class FlowPdfFailed extends ScanFlowState {
  const FlowPdfFailed(this.failure);

  final ScanPdfFailure failure;

  @override
  bool get isFinal => true;
}

/// The user stopped the flow. Pictures already stored stay; no PDF is made
/// for a flow cancelled before it; [pdf] is set when it was already stored.
final class FlowCancelled extends ScanFlowState {
  const FlowCancelled(this.stage, {this.pdf});

  final ScanFlowStage stage;
  final StoredPdf? pdf;

  @override
  bool get isFinal => true;
}

/// Stops a flow. Cancelling during the send also stops the send.
class ScanFlowCancellation {
  final mail = MailCancellation();

  bool get isCancelled => mail.isCancelled;
  Future<void> get whenCancelled => mail.whenCancelled;

  void cancel() => mail.cancel();
}
