/// Every tunable of the PDF in one place (ADR-016, ADR-017).
abstract final class PdfConfig {
  /// Resolution that turns the pixels of the working copy into the size of the
  /// page: `points = pixels * 72 / dpi`. The working copy has a long side of at
  /// most 2560 px; at 200 dpi a full-page photo is about 13 in on its long side
  /// (A4 is 11.7 in at 219 dpi), which every viewer fits to the screen. The
  /// ratio of the page is exactly the ratio of the picture, so nothing is
  /// stretched, whatever the shape of the photographed paper.
  static const dpi = 200.0;

  /// PDF user units per inch.
  static const pointsPerInch = 72.0;

  /// Share of the height of a text box that lies below the baseline
  /// (descenders and the margin the detector adds around the letters).
  static const baselineFromBottom = 0.22;

  /// Size of the hidden font as a share of the height of the text box.
  static const fontHeightShare = 0.72;

  /// A text box thinner than this many pixels is ignored: it cannot carry a
  /// readable word and would only add noise to the text layer.
  static const minBoxPixels = 2.0;
}
