import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/entities/pdf_page_input.dart';
import '../../domain/entities/stored_scan.dart';
import '../../domain/ports/open_pdf.dart';
import '../../domain/usecases/load_settings.dart';
import '../../domain/usecases/recognize_pages.dart';
import '../../domain/usecases/store_scan_pdf.dart';
import 'scan_result_state.dart';

/// Makes the PDF of a scan whose photos are already stored.
///
/// Waits until the OCR has an outcome for every page (the engine's own limit of
/// 45 s per page bounds the wait; [skipText] ends it at once), then writes the
/// PDF, copies it into `./pdf` and deletes the working copies of the pictures.
/// Whatever happens here, the photos stay: a failure is a state, never a
/// crash, and [retry] runs the last two steps again.
class ScanResultCubit extends Cubit<ScanResultState> {
  ScanResultCubit({
    required this.scan,
    required this._session,
    required this._loadSettings,
    required this._storePdf,
    required this._openPdf,
    required this._logger,
  }) : super(const ScanResultState());

  final StoredScan scan;
  final OcrSession? _session;
  final LoadSettings _loadSettings;
  final StoreScanPdf _storePdf;
  final OpenPdf _openPdf;
  final AppLogger _logger;

  StreamSubscription<OcrSessionSnapshot>? _progress;
  var _running = false;

  /// Starts waiting for the text and then makes the PDF.
  Future<void> start() async {
    final session = _session;
    if (session == null) {
      // No reading was started for this scan, so there is no picture to put in.
      emit(
        state.copyWith(
          phase: ScanPdfPhase.failed,
          failure: ScanPdfFailure.pageImageMissing,
        ),
      );
      return;
    }
    _showProgress(session.snapshot);
    _progress = session.snapshots.listen(_showProgress);
    final done = await session.finished;
    unawaited(_progress?.cancel());
    _progress = null;
    if (isClosed) return;
    await _makePdf(done);
  }

  /// Ends the wait for the text: pages not read yet go in without text.
  Future<void> skipText() async {
    if (state.phase != ScanPdfPhase.readingText) return;
    _session?.stopReading();
  }

  /// Runs the failed step again (the readings are kept in the session).
  Future<void> retry() async {
    final session = _session;
    if (state.phase != ScanPdfPhase.failed || session == null) return;
    await _makePdf(await session.finished);
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

  void _showProgress(OcrSessionSnapshot snapshot) {
    if (isClosed || state.phase != ScanPdfPhase.readingText) return;
    final read = snapshot.pages
        .where((p) => p.status == OcrPageStatus.done)
        .length;
    emit(state.copyWith(pagesRead: read, pagesTotal: snapshot.pages.length));
  }

  Future<void> _makePdf(OcrSessionSnapshot done) async {
    if (_running || isClosed) return;
    _running = true;
    try {
      emit(
        state.copyWith(
          phase: ScanPdfPhase.creating,
          pagesRead: done.pages.length,
          pagesTotal: done.pages.length,
          clearFailure: true,
        ),
      );
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

      final folder = (await _loadSettings()).storageFolder;
      if (folder == null) {
        throw const ScanPdfException(ScanPdfFailure.noAccess);
      }
      final stored = await _storePdf(
        folder: folder,
        stem: scan.stem,
        pages: pages,
      );
      // The pictures are in the PDF now: no copy of them stays in the cache.
      await _session?.releaseWorkingCopies();
      if (isClosed) return;
      emit(state.copyWith(phase: ScanPdfPhase.saved, pdf: stored));
    } on ScanPdfException catch (error) {
      _fail(error.failure);
    } catch (error, stackTrace) {
      _logger.error('Making the PDF failed unexpectedly', error, stackTrace);
      _fail(ScanPdfFailure.buildFailed);
    } finally {
      _running = false;
    }
  }

  void _fail(ScanPdfFailure failure) {
    if (isClosed) return;
    emit(state.copyWith(phase: ScanPdfPhase.failed, failure: failure));
  }

  @override
  Future<void> close() {
    unawaited(_progress?.cancel());
    _progress = null;
    return super.close();
  }
}
