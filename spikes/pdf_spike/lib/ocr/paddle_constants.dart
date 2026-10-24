/// Properties of the PP-OCRv5 models and of the DB post-processing. These are
/// part of the models, not tunables of the app (those are in `OcrConfig`).
abstract final class PaddleConstants {
  /// Height of a recognition crop in pixels (the recogniser's input height).
  static const recHeight = 48;

  /// Upper limit of the width of a recognition crop.
  static const maxRecWidth = 2048;

  /// Narrowest crop (a box much taller than wide is still given this width).
  static const minRecWidth = 16;

  /// Detection and recognition inputs are multiples of this.
  static const detMultiple = 32;

  /// Pixels of the probability map above this belong to text.
  static const detThreshold = 0.3;

  /// A text region is kept when the mean probability inside is at least this.
  static const boxThreshold = 0.6;

  /// A region smaller than this many pixels (on the probability map) is noise.
  static const minRegionPixels = 12;

  /// A box whose short side (on the probability map) is below this is noise.
  static const minBoxSide = 3.0;

  /// DB unclip ratio: grows the shrunk text kernel back to the text size.
  static const unclipRatio = 1.5;

  /// Detection input normalisation (ImageNet), per channel in the order of the
  /// planes of the tensor: B, G, R.
  static const detMean = [0.406, 0.456, 0.485];
  static const detStd = [0.225, 0.224, 0.229];

  /// Recognition input: `(value / 255 - 0.5) / 0.5`, that is `value / 127.5 - 1`.
  static const recScale = 1 / 127.5;
}
