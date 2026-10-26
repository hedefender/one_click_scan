import 'package:equatable/equatable.dart';

import '../../core/errors/app_exceptions.dart';
import '../../domain/entities/pdf_page_input.dart';
import '../../domain/ports/open_pdf.dart';

enum ScanPdfPhase {
  /// Waiting for the OCR of the pages (or for the end of its time limit).
  readingText,

  /// The PDF is being written and copied into the user's folder.
  creating,
  saved,
  failed,
}

class ScanResultState extends Equatable {
  const ScanResultState({
    this.phase = ScanPdfPhase.readingText,
    this.pagesRead = 0,
    this.pagesTotal = 0,
    this.pdf,
    this.failure,
    this.openProblem,
  });

  final ScanPdfPhase phase;

  /// Pages with an outcome, of [pagesTotal] pages in the scan.
  final int pagesRead;
  final int pagesTotal;

  /// Set when [phase] is [ScanPdfPhase.saved].
  final StoredPdf? pdf;

  /// Set when [phase] is [ScanPdfPhase.failed].
  final ScanPdfFailure? failure;

  /// The last attempt to open the PDF did not work (no viewer, or an error).
  final OpenPdfResult? openProblem;

  /// The PDF is still being made: leaving the screen would lose it.
  bool get busy =>
      phase == ScanPdfPhase.readingText || phase == ScanPdfPhase.creating;

  /// The page being read, 1-based, for the text "page 2 of 3".
  int get pageInProgress =>
      pagesTotal == 0 ? 1 : (pagesRead + 1).clamp(1, pagesTotal);

  ScanResultState copyWith({
    ScanPdfPhase? phase,
    int? pagesRead,
    int? pagesTotal,
    StoredPdf? pdf,
    ScanPdfFailure? failure,
    OpenPdfResult? openProblem,
    bool clearOpenProblem = false,
    bool clearFailure = false,
  }) {
    return ScanResultState(
      phase: phase ?? this.phase,
      pagesRead: pagesRead ?? this.pagesRead,
      pagesTotal: pagesTotal ?? this.pagesTotal,
      pdf: pdf ?? this.pdf,
      failure: clearFailure ? null : failure ?? this.failure,
      openProblem: clearOpenProblem ? null : openProblem ?? this.openProblem,
    );
  }

  @override
  List<Object?> get props => [
    phase,
    pagesRead,
    pagesTotal,
    pdf,
    failure,
    openProblem,
  ];
}
