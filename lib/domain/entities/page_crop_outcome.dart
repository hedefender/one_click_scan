import 'package:equatable/equatable.dart';

import '../imaging/quad.dart';

/// Why a page kept the whole frame.
enum WholeFrameReason {
  /// A candidate was found but its confidence is below the threshold.
  lowConfidence,

  /// No candidate outline at all.
  noPageFound,

  /// An exception or a lack of memory in the crop.
  failed,

  /// The crop took longer than `PageCropConfig.timeout`.
  timedOut,

  /// The user cancelled or undid the page while it was being cropped.
  cancelled,
}

/// What the crop made of one page (ADR-029).
sealed class PageCropOutcome extends Equatable {
  const PageCropOutcome();
}

/// The page was found and straightened into a new picture.
class PageCropped extends PageCropOutcome {
  const PageCropped({
    required this.quad,
    required this.confidence,
    required this.width,
    required this.height,
  });

  /// The outline found, in pixels of the working copy.
  final Quad quad;
  final double confidence;

  /// Pixels of the straightened picture as written.
  final int width;
  final int height;

  @override
  List<Object?> get props => [confidence, width, height];
}

/// The page keeps the whole frame: nothing is lost.
class PageWholeFrame extends PageCropOutcome {
  const PageWholeFrame(this.reason);

  final WholeFrameReason reason;

  @override
  List<Object?> get props => [reason];
}
