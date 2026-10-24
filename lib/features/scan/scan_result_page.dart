import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation/route_paths.dart';
import '../../domain/entities/stored_scan.dart';
import '../../domain/usecases/recognize_pages.dart';
import '../../presentation/l10n/app_strings.dart';
import '../../presentation/state/settings_cubit.dart';
import '../../services/scan_files/scan_temp_store.dart';
import 'scan_keys.dart';
import 'scan_page.dart' show PageThumbnail;
import 'scan_result_args.dart';

/// Shows what was stored. The cached shots are kept only to draw the
/// thumbnails and are deleted when this screen is left; the background
/// reading of the pages (OCR) ends with it too.
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

    return Scaffold(
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
                  onPressed: () => context.go(RoutePaths.home),
                  child: Text(strings.scanBackHome),
                ),
              ),
            ),
          ],
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
