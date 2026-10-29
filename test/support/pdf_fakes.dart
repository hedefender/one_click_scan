import 'dart:async';

import 'package:one_click_scan/core/errors/app_exceptions.dart';
import 'package:one_click_scan/domain/entities/pdf_page_input.dart';
import 'package:one_click_scan/domain/ports/open_pdf.dart';
import 'package:one_click_scan/domain/ports/pdf_builder.dart';
import 'package:one_click_scan/services/pdf/pdf_services.dart';

/// A PDF writer that writes nothing: it records the pages it was given and
/// answers with a made-up file.
class FakePdfBuilder implements PdfBuilder {
  /// Thrown by [build] when set.
  ScanPdfException? failWith;

  /// When set, [build] waits for it (the writer cannot be interrupted).
  Completer<void>? gate;

  final List<List<PdfPageInput>> builds = [];
  final List<String> discarded = [];
  int purgeCalls = 0;
  var _n = 0;

  @override
  Future<BuiltPdf> build(List<PdfPageInput> pages) async {
    await gate?.future;
    final failure = failWith;
    if (failure != null) throw failure;
    builds.add(pages);
    return BuiltPdf(
      path: 'pdf_work/fake_${++_n}.pdf',
      pageCount: pages.length,
      textPageCount: pages.where((p) => p.hasText).length,
      byteSize: 123456,
    );
  }

  @override
  Future<void> discard(String path) async => discarded.add(path);

  @override
  Future<void> purgeAll() async => purgeCalls++;
}

class FakeOpenPdf implements OpenPdf {
  OpenPdfResult result = OpenPdfResult.opened;
  final List<String> opened = [];

  @override
  Future<OpenPdfResult> open(String uri) async {
    opened.add(uri);
    return result;
  }
}

/// Fake PDF writer and viewer as a bundle for `buildTestContainer`.
class PdfTestRig {
  final builder = FakePdfBuilder();
  final opener = FakeOpenPdf();

  PdfServices get services => PdfServices(builder: builder, opener: opener);
}
