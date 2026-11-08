import 'package:equatable/equatable.dart';

import '../mail/mail_provider.dart';
import '../mail/mail_size_policy.dart';
import 'page_budget_config.dart';

/// What the budget says about a scan with a given number of pages.
class PageBudget extends Equatable {
  const PageBudget({
    required this.pageCount,
    required this.maxPages,
    required this.estimatedBytes,
    required this.limitBytes,
    required this.showCounter,
    required this.nearLimitPages,
  });

  /// Pages taken so far.
  final int pageCount;

  /// "XX": how many pages the scan may have, by the estimate (1 to the hard
  /// maximum). Moves up and down as the pages are measured.
  final int maxPages;

  /// Estimated size of the PDF of the pages so far.
  final int estimatedBytes;

  /// The biggest PDF the provider takes.
  final int limitBytes;

  /// The counter shows as "n/XX" instead of "n".
  final bool showCounter;

  final int nearLimitPages;

  /// No more pages may be taken. Never removes pages: when the estimate falls
  /// below the pages already there, the limit is simply reached.
  bool get reached => pageCount >= maxPages;

  /// Pages that still fit, by the estimate.
  int get remaining => reached ? 0 : maxPages - pageCount;

  /// The "still fits about N pages" message is due.
  bool get nearLimit =>
      pageCount > 0 && !reached && remaining <= nearLimitPages;

  @override
  List<Object?> get props => [
    pageCount,
    maxPages,
    estimatedBytes,
    limitBytes,
    showCounter,
    nearLimitPages,
  ];
}

/// Estimates how many pages fit in the PDF a provider takes (ADR-032).
///
/// `XX = min(hardMax, floor((limit * margin - fixed) / average page))`, where the
/// average page is the mean size of the pages measured so far plus the page
/// overhead (a page not measured yet counts as that average). Pure: no UI, no
/// plugin; the limit and the config are injected.
class PageBudgetEstimator extends Equatable {
  const PageBudgetEstimator({
    required this.limitBytes,
    this.config = const PageBudgetConfig(),
  });

  /// The limit of [provider], from the same source the send uses.
  factory PageBudgetEstimator.forProvider(
    MailProvider provider, {
    PageBudgetConfig config = const PageBudgetConfig(),
  }) => PageBudgetEstimator(
    limitBytes: MailSizePolicy.maxAttachmentBytes(provider),
    config: config,
  );

  /// The smallest limit of [providers]: for a user who has not chosen one.
  factory PageBudgetEstimator.strictest(
    Iterable<MailProvider> providers, {
    PageBudgetConfig config = const PageBudgetConfig(),
  }) => PageBudgetEstimator(
    limitBytes: providers
        .map(MailSizePolicy.maxAttachmentBytes)
        .reduce((a, b) => a < b ? a : b),
    config: config,
  );

  /// Largest PDF in bytes (not the message).
  final int limitBytes;
  final PageBudgetConfig config;

  /// [pageBytes]: one entry per page in order, the size of the picture that
  /// goes in the PDF, or null while it is not known yet.
  PageBudget evaluate(List<int?> pageBytes) {
    final known = pageBytes.nonNulls.toList();
    final averagePicture = known.isEmpty
        ? config.fallbackPageBytes
        : known.reduce((a, b) => a + b) / known.length;
    final perPage = averagePicture + config.perPageOverheadBytes;
    final room = limitBytes * config.margin - config.fixedOverheadBytes;
    final fits = room <= 0 ? 0 : (room / perPage).floor();
    final maxPages = fits.clamp(1, config.hardMaxPages);

    var estimated = pageBytes.isEmpty ? 0 : config.fixedOverheadBytes;
    for (final bytes in pageBytes) {
      estimated += bytes == null
          ? perPage.round()
          : bytes + config.perPageOverheadBytes;
    }
    final count = pageBytes.length;
    return PageBudget(
      pageCount: count,
      maxPages: maxPages,
      estimatedBytes: estimated,
      limitBytes: limitBytes,
      showCounter:
          count >= config.showFromPage ||
          (count > 0 && estimated > limitBytes * config.earlyShowFraction),
      nearLimitPages: config.nearLimitPages,
    );
  }

  @override
  List<Object?> get props => [
    limitBytes,
    config.hardMaxPages,
    config.margin,
    config.showFromPage,
    config.earlyShowFraction,
    config.nearLimitPages,
    config.fallbackPageBytes,
    config.perPageOverheadBytes,
    config.fixedOverheadBytes,
  ];
}
