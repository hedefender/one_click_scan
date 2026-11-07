import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/entities/scan_flow_mode.dart';
import '../../domain/entities/stored_scan.dart';
import '../../domain/lighting/enhancement_gate.dart';
import '../../domain/ports/open_pdf.dart';
import '../../domain/ports/scan_file_store.dart';
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
    this.darkPages = const <String>[],
    required this._session,
    required this._loadSettings,
    required this._scanAndSend,
    required this._discardScan,
    required this._openPdf,
    required this._fileStore,
    required this._logger,
  }) : super(ScanFlowViewState(darkPages: darkPages));

  final StoredScan scan;

  /// Pages flagged dark that have no decision (preview mode).
  final List<String> darkPages;
  final OcrSession? _session;
  final LoadSettings _loadSettings;
  final ScanAndSend _scanAndSend;
  final DiscardScan _discardScan;
  final OpenPdf _openPdf;
  final ScanFileStore _fileStore;
  final AppLogger _logger;

  StreamSubscription<ScanFlowState>? _subscription;
  ScanFlowCancellation? _cancellation;

  /// Starts the flow. Also the "try again" of a failed PDF.
  Future<void> start() async {
    if (_subscription != null) return;
    final settings = await _loadSettings();
    if (isClosed) return;
    final preview = settings.effectiveScanFlowMode == ScanFlowMode.preview;
    emit(
      state.copyWith(
        previewMode: preview,
        lightFix: preview && darkPages.isNotEmpty
            ? LightFix.offered
            : LightFix.none,
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

  /// "Correct the light" of the banner (ADR-030): the dark pages are read
  /// again in their corrected version (the version with more words is kept per
  /// page), and when a corrected picture was kept the PDF is made again. The old
  /// PDF is deleted first, by its URI, so the new one has the same name; if the
  /// new one fails, the usual "try again" of the PDF is there and the pictures
  /// are untouched. The originals are never read or changed.
  Future<void> improveLight() async {
    final session = _session;
    if (!state.canOfferLightFix || session == null) return;
    emit(state.copyWith(lightFix: LightFix.working));
    var applied = 0;
    var kept = 0;
    for (final key in darkPages) {
      if (isClosed) return;
      final used = await session.requestEnhance(key);
      final page = session.snapshot.pages.where((p) => p.key == key);
      final outcome = page.isEmpty ? null : page.first.enhancement;
      if (used) applied++;
      if (outcome == EnhancementOutcome.keptOriginal) kept++;
    }
    if (isClosed) return;
    // Numbers only.
    _logger.debug('Light correction: $applied applied, $kept kept original');
    if (applied == 0) {
      emit(
        state.copyWith(
          lightFix: kept > 0 ? LightFix.keptOriginal : LightFix.failed,
        ),
      );
      return;
    }
    final old = state.pdf;
    if (old != null) {
      try {
        await _fileStore.deleteByUri(old.uri);
      } catch (error, stackTrace) {
        _logger.error(
          'The old PDF was not deleted',
          error.runtimeType,
          stackTrace,
        );
      }
    }
    emit(state.copyWith(clearPdf: true, lightFix: LightFix.improved));
    _launch();
  }

  /// "Keep as is": the pages stay as they are, the banner goes.
  void keepDark() {
    if (state.lightFix != LightFix.offered) return;
    emit(state.copyWith(lightFix: LightFix.dismissed));
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
    // The preview keeps the straightened pages in the cache to show them
    // (ADR-029); a discarded scan must leave no picture of it anywhere.
    await _session?.releaseWorkingCopies();
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
