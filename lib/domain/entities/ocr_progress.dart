import 'package:equatable/equatable.dart';

enum OcrStage {
  /// Models are being loaded (first page after start-up).
  loadingModels,

  /// The upright working copy is being made.
  preparingImage,

  /// Looking for text boxes.
  detecting,

  /// Reading box [OcrProgress.done] of [OcrProgress.total].
  recognizing,
}

/// A progress report. Shown as text ("line 12 of 51"), not as a spinner.
class OcrProgress extends Equatable {
  const OcrProgress(this.stage, {this.done = 0, this.total = 0});

  final OcrStage stage;
  final int done;
  final int total;

  @override
  List<Object?> get props => [stage, done, total];
}
