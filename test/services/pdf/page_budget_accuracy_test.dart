import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:one_click_scan/domain/pdf/pdf_text_layout.dart';
import 'package:one_click_scan/domain/scan/page_budget_config.dart';
import 'package:one_click_scan/domain/scan/page_budget_estimator.dart';
import 'package:one_click_scan/services/pdf/pdf_writer.dart';

/// How good is the page budget (ADR-032)? Synthetic pages of very different
/// content (a nearly blank page, a text page, a photo with texture) are made
/// into a real PDF with the real writer, and the estimate is compared with the
/// real size.
///
/// Two errors are measured and printed (`PAGEBUDGET ...`, copied to
/// `PHASE_6_3_VALIDATION.md`):
///
///  * **sum error**: the estimate of the PDF of the pages already taken (their
///    measured pictures plus the overheads) against the real PDF;
///  * **projection error**: what the budget expects for a scan of N pages from
///    the first k pages, against the real PDF of those N pages. This is the
///    error that decides the margin: the later pages are not known yet.
///
/// The pictures are what is measured on a real shot of the phone only in
/// kind (JPEG, quality 95); the real sizes per page wait for the phone check.
void main() {
  late Directory dir;
  late Uint8List font;

  setUpAll(() {
    font = File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync();
  });

  setUp(() => dir = Directory.systemTemp.createTempSync('page_budget_acc'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// A page picture of the given [kind]; the pixels are what the working copy
  /// would have in kind (the size here is smaller than on the phone to keep the
  /// test fast, the bytes per pixel are what matters).
  String makePicture(int index, String kind, Random random) {
    const width = 1280;
    const height = 960;
    final image = img.Image(width: width, height: height);
    switch (kind) {
      case 'blank':
        img.fill(image, color: img.ColorRgb8(235, 235, 235));
      case 'text':
        img.fill(image, color: img.ColorRgb8(240, 240, 240));
        for (var y = 40; y < height - 40; y += 28) {
          for (var x = 40; x < width - 40; x += 14) {
            if (random.nextDouble() < 0.7) {
              img.fillRect(
                image,
                x1: x,
                y1: y,
                x2: x + 8,
                y2: y + 14,
                color: img.ColorRgb8(30, 30, 30),
              );
            }
          }
        }
      case 'photo':
        for (final pixel in image) {
          final shade = (120 + 60 * sin(pixel.x / 40) + random.nextInt(60))
              .round();
          pixel
            ..r = shade
            ..g = (shade * 0.9).round()
            ..b = (shade * 0.8).round();
        }
      default:
        throw ArgumentError(kind);
    }
    final path = '${dir.path}/page_$index.jpg';
    File(path).writeAsBytesSync(img.encodeJpg(image, quality: 95));
    return path;
  }

  List<PdfTextRun> words(int count) => [
    for (var i = 0; i < count; i++)
      PdfTextRun(
        text: 'Word$i',
        x: 36.0 + (i % 10) * 40,
        y: 700.0 - (i ~/ 10) * 14,
        angle: 0,
        fontSize: 10,
        width: 36,
      ),
  ];

  Future<int> realPdf(List<PdfPageJob> pages, String name) => writePdf(
    PdfJob(pages: pages, fontBytes: font, outputPath: '${dir.path}/$name.pdf'),
  );

  PdfPageJob job(String path, int wordCount) => PdfPageJob(
    imagePath: path,
    widthPx: 1280,
    heightPx: 960,
    runs: words(wordCount),
  );

  test('overheads: one PDF with several pages, measured', () async {
    final random = Random(1);
    final kinds = ['blank', 'text', 'photo', 'text', 'blank', 'photo'];
    final paths = [
      for (var i = 0; i < kinds.length; i++) makePicture(i, kinds[i], random),
    ];
    final sizes = [for (final path in paths) File(path).lengthSync()];
    final jobs = [for (final path in paths) job(path, 120)];
    final one = await realPdf(jobs.sublist(0, 1), 'one');
    final all = await realPdf(jobs, 'all');
    final perPage =
        (all - one) / (jobs.length - 1) -
        sizes.sublist(1).reduce((a, b) => a + b) / (jobs.length - 1);
    final fixed = one - sizes.first - perPage;
    // ignore: avoid_print
    print(
      'PAGEBUDGET overhead: fixed ~ ${fixed.round()} B, per page (120 words) '
      '~ ${perPage.round()} B',
    );
    expect(fixed, lessThan(PageBudgetConfig.defaultFixedOverheadBytes * 2));
    expect(perPage, lessThan(PageBudgetConfig.defaultPerPageOverheadBytes * 2));
  });

  test('sum error and projection error on mixed scans', () async {
    final random = Random(7);
    final sumErrors = <double>[];
    final projectionErrors = <double>[];
    // Scans of 5, 15 and 25 pages with different mixes.
    for (final (count, mix) in [
      (5, ['text', 'text', 'blank', 'photo', 'text']),
      (15, ['text', 'photo', 'blank']),
      (25, ['text', 'text', 'text', 'photo', 'blank']),
    ]) {
      final paths = [
        for (var i = 0; i < count; i++)
          makePicture(1000 * count + i, mix[i % mix.length], random),
      ];
      final sizes = [for (final path in paths) File(path).lengthSync()];
      final jobs = [
        for (final path in paths) job(path, 60 + random.nextInt(200)),
      ];
      final real = await realPdf(jobs, 'scan$count');
      const estimator = PageBudgetEstimator(limitBytes: 18 * 1024 * 1024);

      final sum = estimator.evaluate(sizes).estimatedBytes;
      final sumError = (sum - real) / real;
      sumErrors.add(sumError);

      // From the first k pages to the whole scan.
      var worst = 0.0;
      for (final k in [1, 2, 3, 5]) {
        if (k >= count) continue;
        final known = sizes.sublist(0, k);
        final perPage =
            known.reduce((a, b) => a + b) / k +
            PageBudgetConfig.defaultPerPageOverheadBytes;
        final projected =
            PageBudgetConfig.defaultFixedOverheadBytes + perPage * count;
        final error = (projected - real) / real;
        // ignore: avoid_print
        print(
          'PAGEBUDGET $count pages from first $k: projected '
          '${(projected / 1024).round()} KB, real ${(real / 1024).round()} KB, '
          'error ${(error * 100).toStringAsFixed(1)} %',
        );
        if (error.abs() > worst.abs()) worst = error;
        projectionErrors.add(error);
      }
      // ignore: avoid_print
      print(
        'PAGEBUDGET $count pages: sum estimate ${(sum / 1024).round()} KB, '
        'real ${(real / 1024).round()} KB, error '
        '${(sumError * 100).toStringAsFixed(2)} %',
      );
    }
    double mean(List<double> v) =>
        v.map((e) => e.abs()).reduce((a, b) => a + b) / v.length;
    double max(List<double> v) =>
        v.map((e) => e.abs()).reduce((a, b) => a > b ? a : b);
    // ignore: avoid_print
    print(
      'PAGEBUDGET sum error: mean ${(mean(sumErrors) * 100).toStringAsFixed(2)} %, '
      'max ${(max(sumErrors) * 100).toStringAsFixed(2)} %',
    );
    // ignore: avoid_print
    print(
      'PAGEBUDGET projection error: mean '
      '${(mean(projectionErrors) * 100).toStringAsFixed(1)} %, max '
      '${(max(projectionErrors) * 100).toStringAsFixed(1)} %',
    );
    // The sum of measured pictures must be close to the real file.
    expect(max(sumErrors), lessThan(0.05));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'a scan taken up to the limit of the budget stays under the real limit',
    () {
      // Page sizes (bytes of the picture) in kind: a text page and a blank page
      // are much smaller than a photo page. Scaled to a working copy of the
      // phone (2560 px, quality 95): a photo page about 2 MB.
      const photo = 2000 * 1024;
      const text = 700 * 1024;
      const blank = 120 * 1024;
      const limit = 18 * 1024 * 1024; // about the limit of Gmail (18.2 MB)
      for (final margin in [0.8, 0.85, 0.9, 0.95]) {
        for (final (name, sample) in <(String, int Function(Random))>[
          // Same kind of page, plus or minus 25 %.
          (
            'uniform text pages',
            (r) => (text * (0.75 + r.nextDouble() * 0.5)).round(),
          ),
          // A real mix: mostly text, some photos, some nearly blank.
          (
            'mixed pages',
            (r) {
              final x = r.nextDouble();
              final base = x < 0.6 ? text : (x < 0.8 ? photo : blank);
              return (base * (0.75 + r.nextDouble() * 0.5)).round();
            },
          ),
          // The worst case for the budget: small pages first, photos after.
          (
            'small first, then photos',
            (r) => r.nextDouble() < 0.5 ? blank : photo,
          ),
        ]) {
          final random = Random(42);
          final estimator = PageBudgetEstimator(
            limitBytes: limit,
            config: PageBudgetConfig(margin: margin),
          );
          var over = 0;
          var fill = 0.0;
          var worst = 0.0;
          const runs = 2000;
          for (var run = 0; run < runs; run++) {
            final pages = <int>[];
            final smallFirst = name.startsWith('small first');
            while (!estimator.evaluate(pages).reached) {
              pages.add(
                smallFirst && pages.length < 4 ? blank : sample(random),
              );
            }
            final real =
                pages.reduce((a, b) => a + b) +
                pages.length * 1069 +
                3566; // measured overheads
            final ratio = real / limit;
            fill += ratio;
            if (ratio > 1) over++;
            if (ratio > worst) worst = ratio;
          }
          // ignore: avoid_print
          print(
            'PAGEBUDGET margin $margin, $name: over the limit in '
            '${(over * 100 / runs).toStringAsFixed(1)} % of scans, worst '
            '${(worst * 100).toStringAsFixed(0)} % of the limit, mean fill '
            '${(fill * 100 / runs).toStringAsFixed(0)} %',
          );
        }
      }
    },
  );
}
