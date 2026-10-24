import 'dart:io';

import 'package:one_click_scan/core/logging/app_logger.dart';
import 'package:one_click_scan/domain/entities/ocr_outcome.dart';
import 'package:one_click_scan/domain/ocr/ocr_language_pack_registry.dart';
import 'package:one_click_scan/domain/usecases/prepare_image_for_ocr.dart';
import 'package:one_click_scan/domain/usecases/recognize_pages.dart';
import 'package:one_click_scan/services/ocr/ocr_services.dart';
import 'package:path_provider/path_provider.dart';

import 'synthetic_pages.dart';

/// What the smoke checks found.
class OcrSmokeResult {
  const OcrSmokeResult({
    required this.recall,
    required this.dartPathSize,
    required this.nativePathSize,
    required this.peakRssMb,
    required this.milliseconds,
  });

  final double recall;
  final (int, int) dartPathSize;
  final (int, int) nativePathSize;
  final int peakRssMb;
  final int milliseconds;

  @override
  String toString() =>
      'recall ${(recall * 100).toStringAsFixed(1)}%, '
      'dart path ${dartPathSize.$1}x${dartPathSize.$2}, '
      'native path ${nativePathSize.$1}x${nativePathSize.$2}, '
      'peak RSS $peakRssMb MB, $milliseconds ms';
}

/// Loads the real models, reads one invented page (Dart decode), makes the
/// working copy of a 12 MP photo (native decode). Throws on any failure.
Future<OcrSmokeResult> runOcrSmoke() async {
  final ocr = await createPlatformOcrServices(
    registry: OcrLanguagePackRegistry.standard,
    logger: const DebugAppLogger(),
  );
  final prepare = PrepareImageForOcr(
    headerReader: ocr.headerReader,
    dartMaker: ocr.dartMaker,
    nativeMaker: ocr.nativeMaker,
    workStore: ocr.workStore,
  );
  final recognize = RecognizePages(
    engine: ocr.engine,
    prepare: prepare,
    workStore: ocr.workStore,
  );
  final cache = await getTemporaryDirectory();
  final work = Directory('${cache.path}/ocr_smoke')
    ..createSync(recursive: true);
  final sw = Stopwatch()..start();
  try {
    final page = await renderDocument(greekReceipt.lines);
    final small = writeJpeg('${work.path}/small.jpg', page);
    final session = recognize.start(packId: OcrPackIds.greek)
      ..add('small', small.path)
      ..close();
    final done = await session.finished;
    final outcome = done.pages.single.outcome;
    if (outcome is! OcrSuccess) throw StateError('outcome: $outcome');
    final recall = keyRecall(outcome.result.text, greekReceipt.keyTokens);
    if (recall < 0.95) throw StateError('recall $recall');
    final dartSize = (outcome.result.imageWidth, outcome.result.imageHeight);
    await session.dispose();

    final native = await prepare(writeBigPhoto(work.path, page).path);
    if (native.width != 2560) throw StateError('native width ${native.width}');
    await ocr.workStore.delete(native.path);

    return OcrSmokeResult(
      recall: recall,
      dartPathSize: dartSize,
      nativePathSize: (native.width, native.height),
      peakRssMb: ProcessInfo.maxRss ~/ (1024 * 1024),
      milliseconds: sw.elapsedMilliseconds,
    );
  } finally {
    await ocr.engine.dispose();
    await ocr.workStore.purgeAll();
    if (work.existsSync()) work.deleteSync(recursive: true);
  }
}
