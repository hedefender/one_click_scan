import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_exceptions.dart';
import '../../core/navigation/route_paths.dart';
import '../../domain/entities/stored_scan.dart';
import '../../domain/ports/open_pdf.dart';
import '../../domain/usecases/recognize_pages.dart';
import '../../presentation/l10n/app_strings.dart';
import '../../presentation/state/settings_cubit.dart';
import '../../services/scan_files/scan_temp_store.dart';
import 'scan_keys.dart';
import 'scan_page.dart' show PageThumbnail;
import 'scan_result_args.dart';
import 'scan_result_cubit.dart';
import 'scan_result_state.dart';

/// Shows what was stored and the state of the PDF. The cached shots are kept
/// only to draw the thumbnails and are deleted when this screen is left; the
/// background reading of the pages (OCR) ends with it too. Needs a
/// [ScanResultCubit] above it.
class ScanResultPage extends StatefulWidget {
  const ScanResultPage({super.key, required this.args});

  final ScanResultArgs args;

  StoredScan get result => args.result;
  OcrSession? get ocr => args.ocr;

  @override
  State<ScanResultPage> createState() => _ScanResultPageState();
}

class _ScanResultPageState extends State<ScanResultPage> {
  late final ScanTempStore _tempStore;

  @override
  void initState() {
    super.initState();
    _tempStore = context.read<ScanTempStore>();
  }

  @override
  void dispose() {
    widget.ocr?.dispose();
    _tempStore.delete([
      for (final picture in widget.result.pictures) picture.sourcePath,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final pictures = widget.result.pictures;
    final folderName =
        context.watch<SettingsCubit>().state.storageFolder?.name ??
        strings.homeNotSet;
    final busy = context.select<ScanResultCubit, bool>(
      (cubit) => cubit.state.busy,
    );

    // While the PDF is being made, leaving would lose it: the reading and the
    // working copies end with this screen.
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: Text(strings.scanResultTitle)),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  strings.scanResultSummary(pictures.length, folderName),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Expanded(
                child: ListView(
                  key: ScanKeys.resultList,
                  children: [
                    const _PdfSection(),
                    for (final picture in pictures)
                      ListTile(
                        key: ScanKeys.resultFile(picture.fileName),
                        leading: SizedBox(
                          width: 48,
                          height: 48,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: PageThumbnail(path: picture.sourcePath),
                          ),
                        ),
                        title: Text(picture.fileName),
                        subtitle: _gallerySubtitle(context, picture),
                      ),
                  ],
                ),
              ),
              if (widget.ocr != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      key: ScanKeys.resultOcr,
                      onPressed: () =>
                          context.push(RoutePaths.ocrResult, extra: widget.ocr),
                      child: Text(strings.ocrOpenResult),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: ScanKeys.resultBack,
                    onPressed: busy ? null : () => context.go(RoutePaths.home),
                    child: Text(busy ? strings.pdfWait : strings.scanBackHome),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _gallerySubtitle(BuildContext context, StoredPicture picture) {
    final strings = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return switch (picture.gallery) {
      GalleryCopyStatus.notRequested => null,
      GalleryCopyStatus.saved => Text(strings.scanGallerySaved),
      GalleryCopyStatus.failed => Text(
        strings.scanGalleryFailed,
        style: TextStyle(color: scheme.error),
      ),
    };
  }
}

/// The state of the PDF: text only, and a bar that moves when a page is done
/// (nothing here animates all the time).
class _PdfSection extends StatelessWidget {
  const _PdfSection();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final theme = Theme.of(context);
    return BlocBuilder<ScanResultCubit, ScanResultState>(
      builder: (context, state) {
        final cubit = context.read<ScanResultCubit>();
        final children = <Widget>[
          Text(strings.pdfTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
        ];
        switch (state.phase) {
          case ScanPdfPhase.readingText:
            children.addAll([
              Text(
                key: ScanKeys.pdfStatus,
                strings.pdfReading(state.pageInProgress, state.pagesTotal),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: state.pagesTotal == 0
                    ? 0
                    : state.pagesRead / state.pagesTotal,
              ),
              const SizedBox(height: 8),
              TextButton(
                key: ScanKeys.pdfSkipText,
                onPressed: cubit.skipText,
                child: Text(strings.pdfSkipText),
              ),
            ]);
          case ScanPdfPhase.creating:
            children.add(Text(key: ScanKeys.pdfStatus, strings.pdfCreating));
          case ScanPdfPhase.saved:
            final pdf = state.pdf!;
            children.addAll([
              Text(key: ScanKeys.pdfStatus, strings.pdfSaved(pdf.fileName)),
              Text(
                key: ScanKeys.pdfDetails,
                strings.pdfDetails(pdf.pageCount, _size(pdf.byteSize)),
                style: theme.textTheme.bodySmall,
              ),
              if (pdf.pagesWithoutText > 0) ...[
                const SizedBox(height: 8),
                Text(
                  key: ScanKeys.pdfNoText,
                  strings.pdfPagesWithoutText(pdf.pagesWithoutText),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                key: ScanKeys.pdfNote,
                strings.pdfTextNote,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: ScanKeys.pdfOpen,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text(strings.pdfOpen),
                  onPressed: cubit.openPdf,
                ),
              ),
              if (state.openProblem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    key: ScanKeys.pdfOpenProblem,
                    state.openProblem == OpenPdfResult.noViewer
                        ? strings.pdfOpenNoViewer
                        : strings.pdfOpenFailed,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ]);
          case ScanPdfPhase.failed:
            children.addAll([
              Text(
                key: ScanKeys.pdfFailure,
                _failureText(strings, state.failure),
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: ScanKeys.pdfRetry,
                onPressed: cubit.retry,
                child: Text(strings.pdfRetry),
              ),
            ]);
        }
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        );
      },
    );
  }

  static String _failureText(AppStrings strings, ScanPdfFailure? failure) {
    return switch (failure) {
      ScanPdfFailure.pageImageMissing => strings.pdfFailedImage,
      ScanPdfFailure.unsupported => strings.pdfFailedUnsupported,
      ScanPdfFailure.noAccess => strings.pdfFailedNoAccess,
      ScanPdfFailure.writeFailed => strings.pdfFailedWrite,
      ScanPdfFailure.buildFailed || null => strings.pdfFailedBuild,
    };
  }

  /// "812 KB" or "1.4 MB".
  static String _size(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).ceil()} KB';
  }
}
