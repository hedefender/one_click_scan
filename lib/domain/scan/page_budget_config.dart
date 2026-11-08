/// Numbers of the page budget of a Multi Page scan (ADR-032). One place, so a
/// test or the phone calibration changes a value without touching the logic.
///
/// The size limit itself is NOT here: it is the limit of the mail provider,
/// `MailSizePolicy.maxAttachmentBytes`, so there is one source for it.
class PageBudgetConfig {
  const PageBudgetConfig({
    this.hardMaxPages = defaultHardMaxPages,
    this.margin = defaultMargin,
    this.showFromPage = defaultShowFromPage,
    this.earlyShowFraction = defaultEarlyShowFraction,
    this.nearLimitPages = defaultNearLimitPages,
    this.fallbackPageBytes = defaultFallbackPageBytes,
    this.perPageOverheadBytes = defaultPerPageOverheadBytes,
    this.fixedOverheadBytes = defaultFixedOverheadBytes,
  });

  /// No scan has more pages than this, whatever their size.
  static const defaultHardMaxPages = 25;

  /// Share of the size limit the estimate may use (the rest absorbs the error
  /// of the estimate; `PHASE_6_3_VALIDATION.md` has the measured error).
  static const defaultMargin = 0.9;

  /// The counter "n/XX" shows from this page on.
  static const defaultShowFromPage = 5;

  /// ...or earlier, once the pages so far use this share of the size limit.
  static const defaultEarlyShowFraction = 0.5;

  /// The "still fits about N pages" message shows with this many pages left
  /// (or fewer).
  static const defaultNearLimitPages = 2;

  /// Size of one page before any page has been measured. A page of the working
  /// size (2560 px, JPEG 95) is about this big in the PDF.
  static const defaultFallbackPageBytes = 1500 * 1024;

  /// What a page adds to the PDF besides its picture (the hidden text and the
  /// page object). Measured in `page_budget_accuracy_test.dart`.
  static const defaultPerPageOverheadBytes = 3 * 1024;

  /// What the PDF has once, whatever its pages (the Noto Sans subset, the
  /// document frame). Measured in `page_budget_accuracy_test.dart`.
  static const defaultFixedOverheadBytes = 24 * 1024;

  final int hardMaxPages;
  final double margin;
  final int showFromPage;
  final double earlyShowFraction;
  final int nearLimitPages;
  final int fallbackPageBytes;
  final int perPageOverheadBytes;
  final int fixedOverheadBytes;
}
