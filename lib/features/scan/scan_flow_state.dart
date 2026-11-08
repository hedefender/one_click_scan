import 'package:equatable/equatable.dart';

import '../../domain/entities/pdf_page_input.dart';
import '../../domain/ports/open_pdf.dart';
import '../../domain/scan/scan_flow.dart';
import '../../domain/usecases/discard_scan.dart';

/// Where the light correction of the dark pages is (preview mode, ADR-030).
enum LightFix {
  /// No dark page, or the decision was made before (One Click).
  none,

  /// Dark pages wait for the user: the banner is shown.
  offered,
  working,

  /// The corrected picture is in the PDF (at least one page).
  improved,

  /// The corrected picture read fewer or as many words: the PDF kept the
  /// original (the safety valve).
  keptOriginal,
  failed,

  /// The user chose "Keep as is".
  dismissed,
}

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
    this.darkPages = const <String>[],
    this.darkNeedsRetake = false,
    this.lightFix = LightFix.none,
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

  /// Keys of the pages flagged dark (see `ScanResultArgs.darkPages`).
  final List<String> darkPages;

  /// See `ScanResultArgs.darkNeedsRetake`.
  final bool darkNeedsRetake;
  final LightFix lightFix;

  /// The banner with "Correct the light" is shown (preview, PDF stored, the
  /// user has not decided).
  bool get canOfferLightFix =>
      previewMode &&
      lightFix == LightFix.offered &&
      darkPages.isNotEmpty &&
      flow is FlowAwaitingDecision &&
      discard == DiscardPhase.none;

  /// Work is running and leaving the screen would lose it.
  bool get busy =>
      discard == DiscardPhase.running ||
      lightFix == LightFix.working ||
      switch (flow) {
        null || FlowRecognizing() || FlowBuildingPdf() => true,
        FlowSending() || FlowSharing() => true,
        _ => false,
      };

  /// The user can stop the flow in every stage (ADR-028).
  bool get canCancel => switch (flow) {
    FlowRecognizing() ||
    FlowBuildingPdf() ||
    FlowSending() => discard != DiscardPhase.running,
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
      lightFix != LightFix.working &&
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
    bool clearPdf = false,
    List<String>? darkPages,
    bool? darkNeedsRetake,
    LightFix? lightFix,
  }) {
    return ScanFlowViewState(
      flow: flow ?? this.flow,
      previewMode: previewMode ?? this.previewMode,
      pdf: clearPdf ? null : pdf ?? this.pdf,
      discard: discard ?? this.discard,
      discardOutcome: discardOutcome ?? this.discardOutcome,
      openProblem: clearOpenProblem ? null : openProblem ?? this.openProblem,
      darkPages: darkPages ?? this.darkPages,
      darkNeedsRetake: darkNeedsRetake ?? this.darkNeedsRetake,
      lightFix: lightFix ?? this.lightFix,
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
    darkPages,
    darkNeedsRetake,
    lightFix,
  ];
}
