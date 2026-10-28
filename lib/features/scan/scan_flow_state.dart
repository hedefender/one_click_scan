import 'package:equatable/equatable.dart';

import '../../domain/entities/pdf_page_input.dart';
import '../../domain/ports/open_pdf.dart';
import '../../domain/scan/scan_flow.dart';
import '../../domain/usecases/discard_scan.dart';

/// What happened to a discard asked for by the user.
enum DiscardPhase { none, running, done }

/// What the result screen shows: the flow after the capture ([flow], from
/// `ScanAndSend`), plus the things the screen itself can start (open the PDF,
/// discard).
class ScanFlowViewState extends Equatable {
  const ScanFlowViewState({
    this.flow,
    this.previewMode = true,
    this.pdf,
    this.discard = DiscardPhase.none,
    this.discardOutcome,
    this.openProblem,
  });

  /// The last state of the flow; null until it has started.
  final ScanFlowState? flow;

  /// The scan is in the preview mode (not One Click): the user can discard.
  final bool previewMode;

  /// The stored PDF, once it exists.
  final StoredPdf? pdf;
  final DiscardPhase discard;

  /// Set when [discard] is [DiscardPhase.done].
  final DiscardOutcome? discardOutcome;

  /// The last attempt to open the PDF did not work (no viewer, or an error).
  final OpenPdfResult? openProblem;

  /// Work is running and leaving the screen would lose it.
  bool get busy =>
      discard == DiscardPhase.running ||
      switch (flow) {
        null || FlowRecognizing() || FlowBuildingPdf() => true,
        FlowSending() || FlowSharing() => true,
        _ => false,
      };

  /// The user can stop the flow (not while the PDF is written).
  bool get canCancel => switch (flow) {
    FlowRecognizing() || FlowSending() => discard != DiscardPhase.running,
    _ => false,
  };

  /// The scan was deleted completely. Never true when something is left.
  bool get discarded =>
      discard == DiscardPhase.done && (discardOutcome?.complete ?? false);

  /// The PDF is stored and the mail section applies (the scan is not gone).
  bool get pdfStored => pdf != null && !discarded;

  /// The preview waits for the user (or the mail did not leave).
  bool get canDiscard =>
      previewMode &&
      pdf != null &&
      discard != DiscardPhase.running &&
      !discarded &&
      switch (flow) {
        FlowAwaitingDecision() => true,
        FlowFinished(:final delivery) => delivery is! DeliverySent,
        FlowCancelled(:final pdf) => pdf != null,
        _ => false,
      };

  ScanFlowViewState copyWith({
    ScanFlowState? flow,
    bool? previewMode,
    StoredPdf? pdf,
    DiscardPhase? discard,
    DiscardOutcome? discardOutcome,
    OpenPdfResult? openProblem,
    bool clearOpenProblem = false,
  }) {
    return ScanFlowViewState(
      flow: flow ?? this.flow,
      previewMode: previewMode ?? this.previewMode,
      pdf: pdf ?? this.pdf,
      discard: discard ?? this.discard,
      discardOutcome: discardOutcome ?? this.discardOutcome,
      openProblem: clearOpenProblem ? null : openProblem ?? this.openProblem,
    );
  }

  @override
  List<Object?> get props => [
    flow,
    previewMode,
    pdf,
    discard,
    discardOutcome,
    openProblem,
  ];
}
