/// Every tunable of the page crop in one place (ADR-029). The values come from
/// the measurements of `docs/IMAGE_SPIKE_RESULTS.md` (sections 3, 4 and 6) and
/// from the phone check of the spike.
abstract final class PageCropConfig {
  /// The crop is used when the confidence of the detection is **at least**
  /// this; below it the page keeps the whole frame. 0.5 is the middle of the
  /// range (0.3 to 0.7) where nothing changed on the 77 synthetic scenes: every
  /// wrong detection scored 0.138 or less and almost every good one 0.955 or
  /// more, so 0.5 leaves the widest margin on both sides.
  ///
  /// Raising it sends more pages to the whole frame (safer, no gain from the
  /// crop); lowering it below about 0.15 lets the wrong detections through (3
  /// cut pages and 4 false crops at 0.0). The only place that applies it is
  /// [trustsDetection].
  static const minConfidence = 0.5;

  /// Longest side of the grey picture the detector works on. The detection
  /// does not need more (the spike used 640 for 1536 x 2048 and 2048 pictures)
  /// and the time grows with the pixels.
  static const detectionSide = 640;

  /// The area part of the confidence rises from [areaLow] to [areaHigh] (the
  /// share of the frame the outline takes). Lower values would also crop small
  /// receipts, but 2 of 4 empty scenes then got a confident crop (spike
  /// section 4.3), so they stay as in the default of the spike.
  static const areaLow = 0.05;
  static const areaHigh = 0.2;

  /// Smallest bright piece (share of the frame) kept as a candidate outline.
  static const minBrightFraction = 0.03;

  /// Candidate outlines of the brightness source kept for scoring.
  static const maxCandidates = 6;

  /// Longest time the crop of one page may take (decode, detection, warp,
  /// write). The spike measured about 0.8 s on the emulator (0.45 s to prepare
  /// and about 0.15 s to detect and warp); this is about ten times that. A page
  /// that needs more keeps the whole frame, so a slow phone costs this at most.
  static const timeout = Duration(seconds: 8);

  /// 35 mm film diagonal in millimetres, to turn the EXIF 35 mm equivalent
  /// focal length into pixels: `focalPx = f35 * frameDiagonalPx / 43.27`.
  static const filmDiagonalMm = 43.27;

  /// How many pages may be prepared (and cropped) and wait for the reading
  /// while the engine reads the one before them. Each waiting page is a file
  /// in the cache, and the preparation of one more page holds a few decoded
  /// copies in memory, so the depth is what bounds the memory of the pipeline.
  /// 2 hides the preparation (about 0.6 s per page) behind the reading (about 1
  /// s per page) with at most 3 pictures in flight besides the one read.
  static const prepareAhead = 2;
}

/// The one rule that says whether a detection is trusted (ADR-029).
bool trustsDetection(double confidence) =>
    confidence >= PageCropConfig.minConfidence;
