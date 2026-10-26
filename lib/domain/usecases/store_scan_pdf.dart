import '../../core/errors/app_exceptions.dart';
import '../../core/logging/app_logger.dart';
import '../entities/pdf_page_input.dart';
import '../entities/storage_folder.dart';
import '../ports/pdf_builder.dart';
import '../ports/scan_file_store.dart';
import '../scan/scan_naming.dart';
import 'store_scan_pages.dart';

/// Makes the PDF of a scan and stores it in `./pdf` of the user's folder
/// under the stem of the scan's pictures (`<stem>.pdf`, ADR-005 and ADR-015).
///
/// The photos are stored before this runs and are never touched by it: a
/// failure here leaves them as they are. An existing file is never replaced
/// (the stem was chosen free in both folders; if a file appeared in between,
/// the name gets a suffix). The PDF in the cache is deleted in every case.
class StoreScanPdf {
  const StoreScanPdf({
    required this.builder,
    required this.fileStore,
    required this.naming,
    required this.logger,
  });

  static const pdfFolder = StoreScanPages.pdfFolder;
  static const _pdfMimeType = 'application/pdf';

  /// How many names are tried when files appear in the folder meanwhile.
  static const _maxNameAttempts = 5;

  final PdfBuilder builder;
  final ScanFileStore fileStore;
  final ScanNaming naming;
  final AppLogger logger;

  /// Throws `ScanPdfException`.
  Future<StoredPdf> call({
    required StorageFolder folder,
    required String stem,
    required List<PdfPageInput> pages,
  }) async {
    if (pages.isEmpty) {
      throw ArgumentError.value(pages, 'pages', 'must not be empty');
    }
    final built = await builder.build(pages);
    try {
      return await _store(folder, stem, built);
    } finally {
      await builder.discard(built.path);
    }
  }

  Future<StoredPdf> _store(
    StorageFolder folder,
    String stem,
    BuiltPdf built,
  ) async {
    try {
      await fileStore.ensureSubfolder(folder, pdfFolder);
      var taken = naming.existingStems(
        await fileStore.listFileNames(folder, pdfFolder),
      );
      for (var attempt = 0; attempt < _maxNameAttempts; attempt++) {
        final fileName = naming.pdfName(naming.availableStem(stem, taken));
        try {
          final uri = await fileStore.copyToFolder(
            folder: folder,
            subfolder: pdfFolder,
            fileName: fileName,
            mimeType: _pdfMimeType,
            sourcePath: built.path,
          );
          return StoredPdf(
            fileName: fileName,
            uri: uri,
            pageCount: built.pageCount,
            textPageCount: built.textPageCount,
            byteSize: built.byteSize,
          );
        } on ScanStoreException catch (error) {
          if (error.failure != ScanStoreFailure.exists) rethrow;
          // Somebody wrote this name since the listing: look again.
          taken = naming.existingStems(
            await fileStore.listFileNames(folder, pdfFolder),
          )..add(fileName.substring(0, fileName.length - '.pdf'.length));
        }
      }
      throw const ScanStoreException(ScanStoreFailure.exists);
    } on ScanStoreException catch (error, stackTrace) {
      logger.error('Storing the PDF failed', error, stackTrace);
      throw ScanPdfException(
        error.failure == ScanStoreFailure.noAccess
            ? ScanPdfFailure.noAccess
            : ScanPdfFailure.writeFailed,
      );
    }
  }
}
