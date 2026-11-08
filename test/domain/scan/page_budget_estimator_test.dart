import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/mail_provider_id.dart';
import 'package:one_click_scan/domain/mail/mail_provider.dart';
import 'package:one_click_scan/domain/mail/mail_size_policy.dart';
import 'package:one_click_scan/domain/scan/page_budget_config.dart';
import 'package:one_click_scan/domain/scan/page_budget_estimator.dart';

const _mb = 1024 * 1024;

/// A config without overheads, so the arithmetic of a test is plain.
const _plain = PageBudgetConfig(
  perPageOverheadBytes: 0,
  fixedOverheadBytes: 0,
  fallbackPageBytes: 1 * _mb,
);

void main() {
  PageBudgetEstimator estimator(int limit, [PageBudgetConfig? config]) =>
      PageBudgetEstimator(limitBytes: limit, config: config ?? _plain);

  group('XX = min(25, floor(limit * margin / average page))', () {
    test('uses the measured average of the pages', () {
      // 10 MB limit, margin 0.9, pages of 1 MB: 9 pages.
      final budget = estimator(10 * _mb).evaluate([_mb, _mb]);
      expect(budget.maxPages, 9);
    });

    test('goes up and down as the pages are measured', () {
      final e = estimator(10 * _mb);
      expect(e.evaluate([_mb]).maxPages, 9);
      expect(e.evaluate([_mb, 3 * _mb]).maxPages, 4); // average 2 MB
      expect(e.evaluate([_mb, 3 * _mb, 100 * 1024]).maxPages, greaterThan(4));
    });

    test('a page not measured yet counts as the average of the others', () {
      final e = estimator(10 * _mb);
      final withUnknown = e.evaluate([2 * _mb, null, null]);
      final withKnown = e.evaluate([2 * _mb, 2 * _mb, 2 * _mb]);
      expect(withUnknown.maxPages, withKnown.maxPages);
      expect(withUnknown.estimatedBytes, withKnown.estimatedBytes);
    });

    test('before any page is measured the fallback size is used', () {
      expect(estimator(10 * _mb).evaluate([]).maxPages, 9);
      expect(estimator(10 * _mb).evaluate([null, null]).maxPages, 9);
    });

    test('the margin changes the limit', () {
      final loose = estimator(
        10 * _mb,
        const PageBudgetConfig(
          margin: 1.0,
          perPageOverheadBytes: 0,
          fixedOverheadBytes: 0,
        ),
      );
      final tight = estimator(
        10 * _mb,
        const PageBudgetConfig(
          margin: 0.5,
          perPageOverheadBytes: 0,
          fixedOverheadBytes: 0,
        ),
      );
      expect(loose.evaluate([_mb]).maxPages, 10);
      expect(tight.evaluate([_mb]).maxPages, 5);
    });

    test('the overheads are counted', () {
      final e = estimator(
        10 * _mb,
        const PageBudgetConfig(
          perPageOverheadBytes: _mb ~/ 2,
          fixedOverheadBytes: _mb,
        ),
      );
      // (10 * 0.9 - 1) / 1.5 = 5.33
      expect(e.evaluate([_mb]).maxPages, 5);
      expect(e.evaluate([_mb]).estimatedBytes, _mb + _mb + _mb ~/ 2);
    });

    test('very small pages: the hard maximum of 25 holds', () {
      final budget = estimator(18 * _mb).evaluate([1, 1, 1]);
      expect(budget.maxPages, 25);
      expect(PageBudgetConfig.defaultHardMaxPages, 25);
    });

    test('the hard maximum is injectable', () {
      final e = estimator(
        18 * _mb,
        const PageBudgetConfig(
          hardMaxPages: 7,
          perPageOverheadBytes: 0,
          fixedOverheadBytes: 0,
        ),
      );
      expect(e.evaluate([1]).maxPages, 7);
    });

    test('a page bigger than the whole limit: one page is still allowed', () {
      final budget = estimator(10 * _mb).evaluate([30 * _mb]);
      expect(budget.maxPages, 1);
      expect(budget.reached, isTrue);
      expect(estimator(10 * _mb).evaluate([]).reached, isFalse);
    });
  });

  group('the limit of the provider', () {
    test('comes from the same source as the send check', () {
      for (final id in MailProviderId.values) {
        final provider = MailProviderRegistry.standard.resolve(id);
        expect(
          PageBudgetEstimator.forProvider(provider).limitBytes,
          MailSizePolicy.maxAttachmentBytes(provider),
        );
      }
    });

    test('Gmail takes about 18.2 MB, Outlook and Yahoo about 14.6 MB', () {
      final registry = MailProviderRegistry.standard;
      final gmail = PageBudgetEstimator.forProvider(
        registry.resolve(MailProviderId.gmail),
      );
      final outlook = PageBudgetEstimator.forProvider(
        registry.resolve(MailProviderId.outlook),
      );
      final yahoo = PageBudgetEstimator.forProvider(
        registry.resolve(MailProviderId.yahoo),
      );
      expect(gmail.limitBytes / 1e6, closeTo(18.2, 0.1));
      expect(outlook.limitBytes / 1e6, closeTo(14.6, 0.1));
      expect(yahoo.limitBytes, outlook.limitBytes);
      // The same pages fit fewer times in the smaller limit.
      final pages = [2 * _mb, 2 * _mb];
      expect(
        gmail.evaluate(pages).maxPages,
        greaterThan(outlook.evaluate(pages).maxPages),
      );
    });

    test('without a provider the smallest limit is used', () {
      final strictest = PageBudgetEstimator.strictest(
        MailProviderRegistry.standard.all,
      );
      expect(strictest.limitBytes / 1e6, closeTo(14.6, 0.1));
    });

    test('a test provider with a small limit gives a small budget', () {
      const tiny = MailProvider(
        id: 'tiny',
        smtp: SmtpEndpoint(host: 'x', port: 1, security: SmtpSecurity.plain),
        authKinds: {MailAuthKind.appPassword},
        appPasswordSupport: AppPasswordSupport.supported,
        maxMessageBytes: 3 * _mb,
      );
      final e = PageBudgetEstimator.forProvider(tiny, config: _plain);
      expect(e.evaluate([_mb ~/ 2]).maxPages, lessThan(6));
    });
  });

  group('when the counter shows', () {
    test('only the number before page 5', () {
      final e = estimator(100 * _mb);
      for (var n = 0; n < 5; n++) {
        expect(e.evaluate(List.filled(n, 100)).showCounter, isFalse);
      }
    });

    test('n/XX from page 5', () {
      final e = estimator(100 * _mb);
      expect(e.evaluate(List.filled(5, 100)).showCounter, isTrue);
      expect(e.evaluate(List.filled(8, 100)).showCounter, isTrue);
    });

    test('earlier once the pages use more than half of the limit', () {
      final e = estimator(10 * _mb);
      expect(e.evaluate([2 * _mb, 2 * _mb]).showCounter, isFalse); // 40 %
      expect(e.evaluate([3 * _mb, 3 * _mb]).showCounter, isTrue); // 60 %
      expect(e.evaluate([6 * _mb]).showCounter, isTrue);
    });

    test('an unmeasured page counts toward the half', () {
      final e = estimator(10 * _mb);
      expect(e.evaluate([3 * _mb, 3 * _mb, null]).showCounter, isTrue);
    });
  });

  group('near the limit and at it', () {
    final e = estimator(10 * _mb); // 9 pages of 1 MB

    test('the message is due when two or fewer pages are left', () {
      expect(e.evaluate(List.filled(6, _mb)).nearLimit, isFalse); // 3 left
      expect(e.evaluate(List.filled(7, _mb)).nearLimit, isTrue); // 2 left
      expect(e.evaluate(List.filled(8, _mb)).nearLimit, isTrue); // 1 left
      expect(e.evaluate(List.filled(7, _mb)).remaining, 2);
    });

    test('at the limit the shot is blocked and there is no "still fits"', () {
      final budget = e.evaluate(List.filled(9, _mb));
      expect(budget.reached, isTrue);
      expect(budget.remaining, 0);
      expect(budget.nearLimit, isFalse);
    });

    test(
      'an estimate below the pages already there: reached, none removed',
      () {
        // 12 pages exist; a very heavy page makes the limit smaller than 12.
        final pages = [...List.filled(11, 100 * 1024), 9 * _mb];
        final budget = e.evaluate(pages);
        expect(budget.pageCount, 12);
        expect(budget.maxPages, lessThan(12));
        expect(budget.reached, isTrue);
        expect(budget.remaining, 0);
      },
    );

    test('no page: never near, never reached', () {
      final budget = e.evaluate([]);
      expect(budget.reached, isFalse);
      expect(budget.nearLimit, isFalse);
      expect(budget.showCounter, isFalse);
    });
  });
}
