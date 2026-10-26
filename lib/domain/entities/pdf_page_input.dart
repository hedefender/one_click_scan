import 'package:equatable/equatable.dart';

import 'ocr_line.dart';
import 'ocr_outcome.dart';
import 'upright_image.dart';

/// One page of the PDF: the picture (the upright working copy of the OCR) and
/// what the OCR made of it. A page whose OCR timed out, failed or was
/// cancelled still goes in, without text.
class PdfPageInput extends Equatable {
  const PdfPageInput({required this.image, required this.outcome});

  final UprightImage image;
  final OcrOutcome outcome;

  /// Lines that reach the text layer: those that passed the confidence filter.
  List<OcrLine> get textLines {
    final result = outcome;
    if (result is! OcrSuccess) return const [];
    return result.result.visibleLines;
  }

  /// The page gets hidden text.
  bool get hasText => textLines.isNotEmpty;

  @override
  List<Object?> get props => [image, outcome];
}

/// A PDF written to the app cache, not yet in the user's folder.
class BuiltPdf extends Equatable {
  const BuiltPdf({
    required this.path,
    required this.pageCount,
    required this.textPageCount,
    required this.byteSize,
    this.duration = Duration.zero,
  });

  final String path;
  final int pageCount;

  /// Pages that carry a text layer; the others are the picture only.
  final int textPageCount;
  final int byteSize;

  /// Time the writer needed (numbers for the validation notes).
  final Duration duration;

  int get pagesWithoutText => pageCount - textPageCount;

  @override
  List<Object?> get props => [
    path,
    pageCount,
    textPageCount,
    byteSize,
    duration,
  ];
}

/// The PDF in the user's `./pdf` folder.
class StoredPdf extends Equatable {
  const StoredPdf({
    required this.fileName,
    required this.uri,
    required this.pageCount,
    required this.textPageCount,
    required this.byteSize,
  });

  /// File name inside `./pdf/` (for example `2026-10-21_19-05-12.pdf`).
  final String fileName;

  /// Document URI of the stored file, what the viewer is given.
  final String uri;
  final int pageCount;
  final int textPageCount;
  final int byteSize;

  int get pagesWithoutText => pageCount - textPageCount;

  @override
  List<Object?> get props => [
    fileName,
    uri,
    pageCount,
    textPageCount,
    byteSize,
  ];
}
