import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/entities/scan_flow_mode.dart';
import '../../domain/entities/stored_scan.dart';
import '../../domain/ports/open_pdf.dart';
import '../../domain/scan/scan_flow.dart';
import '../../domain/usecases/discard_scan.dart';
import '../../domain/usecases/load_settings.dart';
import '../../domain/usecases/recognize_pages.dart';
import '../../domain/usecases/scan_and_send.dart';
import 'scan_flow_state.dart';

/// Drives the screen after the capture: it starts [ScanAndSend] and shows its
/// states, and it starts what the user asks for on the screen (cancel, try the
/// PDF again, open the PDF, discard the scan). No flow logic lives here or in
/// the widgets: the order of the steps is the use case's.
///
/// The photos stay whatever happens: a failure is a state, never a crash.
class ScanFlowCubit extends Cubit<ScanFlowViewState> {
  ScanFlowCubit({
    required this.scan,
    required this._session,
    required this._loadSettings,
    required this._scanAndSend,
    required this._discardScan,
    required this._openPdf,
    required this._logger,
  }) : super(const ScanFlowViewState());

  final StoredScan scan;
  final OcrSession? _session;
  final LoadSettings _loadSettings;
  final ScanAndSend _scanAndSend;
  final DiscardScan _discardScan;
  final OpenPdf _openPdf;
  final AppLogger _logger;

  StreamSubscription<ScanFlowState>? _subscription;
  ScanFlowCancellation? _cancellation;

  /// Starts the flow. Also the "try again" of a failed PDF.
  Future<void> start() async {
    if (_subscription != null) return;
    final settings = await _loadSettings();
    if (isClosed) return;
    emit(
      state.copyWith(
        previewMode: settings.effectiveScanFlowMode == ScanFlowMode.preview,
      ),
    );
    _launch();
  }

  /// Runs the flow again after a failed PDF (the readings are kept).
  Future<void> retry() async {
    if (state.flow is! FlowPdfFailed || _subscription != null) return;
    _launch();
  }

  void _launch() {
    final cancellation = ScanFlowCancellation();
    _cancellation = cancellation;
    _subscription = _scanAndSend
        .run(scan: scan, session: _session, cancellation: cancellation)
        .listen(_onFlow, onDone: _onDone);
  }

  void _onFlow(ScanFlowState flow) {
    if (isClosed) return;
    final pdf = switch (flow) {
      FlowAwaitingDecision(:final pdf) => pdf,
      FlowFinished(:final pdf) => pdf,
      FlowCancelled(:final pdf) => pdf,
      _ => null,
    };
    emit(state.copyWith(flow: flow, pdf: pdf));
  }

  void _onDone() {
    _subscription = null;
    _cancellation = null;
  }

  /// Stops the reading or the send. Pictures already stored stay; no PDF is
  /// made when the flow is stopped before it.
  void cancel() {
    if (!state.canCancel) return;
    _cancellation?.cancel();
  }

  /// Ends the wait for the text: pages not read yet go in without text.
  void skipText() {
    if (state.flow is! FlowRecognizing) return;
    _session?.stopReading();
  }

  /// Hands the stored PDF to a viewer.
  Future<void> openPdf() async {
    final pdf = state.pdf;
    if (pdf == null) return;
    final result = await _openPdf.open(pdf.uri);
    if (isClosed) return;
    emit(
      result == OpenPdfResult.opened
          ? state.copyWith(clearOpenProblem: true)
          : state.copyWith(openProblem: result),
    );
  }

  /// Deletes what this scan created (the screen asked the user first). The
  /// outcome says what is left; only a complete one means "deleted".
  Future<void> discard() async {
    if (!state.canDiscard) return;
    emit(state.copyWith(discard: DiscardPhase.running));
    DiscardOutcome outcome;
    try {
      outcome = await _discardScan(scan: scan, pdf: state.pdf);
    } catch (error, stackTrace) {
      // The use case never throws; if it did, nothing is claimed as deleted.
      _logger.error(
        'Discarding failed unexpectedly',
        error.runtimeType,
        stackTrace,
      );
      outcome = DiscardOutcome(
        picturesLeft: scan.pictures.length,
        pdfLeft: state.pdf != null,
        galleryLeft: scan.pictures
            .where((p) => p.gallery == GalleryCopyStatus.saved)
            .length,
      );
    }
    if (isClosed) return;
    emit(state.copyWith(discard: DiscardPhase.done, discardOutcome: outcome));
  }

  @override
  Future<void> close() {
    _cancellation?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    return super.close();
  }
}
