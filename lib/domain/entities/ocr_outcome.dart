import 'package:equatable/equatable.dart';

import 'ocr_result.dart';

/// Why a page could not be read. Never carries user content.
enum OcrFailureReason {
  /// A model file is missing, or its SHA-256 does not match.
  modelUnavailable,

  /// The file could not be read as an image.
  imageUnreadable,

  /// The image is above the size limit; nothing was decoded.
  imageTooLarge,

  /// The platform has no OCR engine.
  unsupported,

  /// Anything else that went wrong inside the engine.
  engineError,
}

/// Result of reading one page. The OCR layer reports through this type and
/// never throws to the UI.
sealed class OcrOutcome extends Equatable {
  const OcrOutcome();

  @override
  List<Object?> get props => const [];
}

final class OcrSuccess extends OcrOutcome {
  const OcrSuccess(this.result);

  final OcrResult result;

  @override
  List<Object?> get props => [result];
}

/// The page exceeded its time limit.
final class OcrTimedOut extends OcrOutcome {
  const OcrTimedOut(this.after);

  final Duration after;

  @override
  List<Object?> get props => [after];
}

final class OcrFailed extends OcrOutcome {
  const OcrFailed(this.reason);

  final OcrFailureReason reason;

  @override
  List<Object?> get props => [reason];
}

final class OcrCancelled extends OcrOutcome {
  const OcrCancelled();
}
