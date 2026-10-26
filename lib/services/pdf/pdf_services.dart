import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/entities/pdf_page_input.dart';
import '../../domain/ports/open_pdf.dart';
import '../../domain/ports/pdf_builder.dart';
import 'android_open_pdf.dart';
import 'dart_pdf_builder.dart';

/// The platform adapters of the PDF, created together like `OcrServices`.
class PdfServices {
  const PdfServices({required this.builder, required this.opener});

  /// No PDF: the default of the container, so tests never write a file or call
  /// a native channel by accident.
  const PdfServices.unsupported()
    : builder = const UnsupportedPdfBuilder(),
      opener = const UnsupportedOpenPdf();

  final PdfBuilder builder;
  final OpenPdf opener;
}

/// The Noto Sans file bundled in the APK (SIL Open Font License 1.1).
const notoSansAsset = 'assets/fonts/NotoSans-Regular.ttf';

Future<PdfServices> createPlatformPdfServices({
  required AppLogger logger,
}) async {
  if (!Platform.isAndroid) return const PdfServices.unsupported();
  final cache = await getTemporaryDirectory();
  return PdfServices(
    builder: DartPdfBuilder(
      workDirectory: Directory(
        '${cache.path}${Platform.pathSeparator}pdf_work',
      ),
      loadFont: () async {
        final data = await rootBundle.load(notoSansAsset);
        return Uint8List.sublistView(data);
      },
      logger: logger,
    ),
    opener: AndroidOpenPdf(),
  );
}

class UnsupportedPdfBuilder implements PdfBuilder {
  const UnsupportedPdfBuilder();

  @override
  Future<BuiltPdf> build(List<PdfPageInput> pages) {
    throw const ScanPdfException(ScanPdfFailure.unsupported);
  }

  @override
  Future<void> discard(String path) async {}

  @override
  Future<void> purgeAll() async {}
}

class UnsupportedOpenPdf implements OpenPdf {
  const UnsupportedOpenPdf();

  @override
  Future<OpenPdfResult> open(String uri) async => OpenPdfResult.failed;
}
