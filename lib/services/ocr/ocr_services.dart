import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/ocr/ocr_language_pack_registry.dart';
import '../../domain/ports/image_header_reader.dart';
import '../../domain/ports/light_enhancer.dart';
import '../../domain/ports/light_meter.dart';
import '../../domain/ports/ocr_engine.dart';
import '../../domain/ports/ocr_work_store.dart';
import '../../domain/ports/page_cropper.dart';
import '../../domain/ports/upright_image_maker.dart';
import '../image/dart_upright_image_maker.dart';
import '../image/file_image_header_reader.dart';
import '../image/io_ocr_work_store.dart';
import '../image/native_upright_image_maker.dart';
import '../imaging/file_light_meter.dart';
import '../imaging/isolate_light_enhancer.dart';
import '../imaging/isolate_page_cropper.dart';
import 'ocr_model_store.dart';
import 'paddle_ocr_engine.dart';
import 'unsupported_ocr_engine.dart';

/// The platform adapters of the OCR, created together (they share the cache
/// folder) like `ScanServices`.
class OcrServices {
  const OcrServices({
    required this.engine,
    required this.workStore,
    required this.headerReader,
    required this.dartMaker,
    required this.nativeMaker,
    this.cropper,
    this.enhancer,
    this.lightMeter,
  });

  /// No OCR: the default of the container, so tests never load a model, touch
  /// the disk or call a native channel by accident.
  const OcrServices.unsupported()
    : engine = const UnsupportedOcrEngine(),
      workStore = const _NoopWorkStore(),
      headerReader = const _NoHeaderReader(),
      dartMaker = const _NoMaker(),
      nativeMaker = const _NoMaker(),
      cropper = null,
      enhancer = null,
      lightMeter = null;

  final OcrEngine engine;
  final OcrWorkStore workStore;
  final ImageHeaderReader headerReader;
  final UprightImageMaker dartMaker;
  final UprightImageMaker nativeMaker;

  /// Finds and straightens the page of a shot (Phase 6.1); null where there is
  /// none, and then every page keeps the whole frame.
  final PageCropper? cropper;

  /// The shadow removal (`flat`), only on request of the user (Phase 6.2);
  /// null where there is none.
  final LightEnhancer? enhancer;

  /// Measures the light of a shot (Phase 6.2); null where there is none, and
  /// then no shot is ever called dark.
  final LightMeter? lightMeter;
}

Future<OcrServices> createPlatformOcrServices({
  required OcrLanguagePackRegistry registry,
  required AppLogger logger,
}) async {
  if (!Platform.isAndroid) return const OcrServices.unsupported();
  final cache = await getTemporaryDirectory();
  final support = await getApplicationSupportDirectory();
  final sep = Platform.pathSeparator;
  final workStore = IoOcrWorkStore(Directory('${cache.path}${sep}ocr_work'));
  return OcrServices(
    engine: PaddleOcrEngine(
      registry: registry,
      logger: logger,
      models: OcrModelStore(
        directory: Directory('${support.path}${sep}ocr_models'),
        loadAsset: rootBundle.load,
        registry: registry,
      ),
    ),
    workStore: workStore,
    headerReader: const FileImageHeaderReader(),
    dartMaker: const DartUprightImageMaker(),
    nativeMaker: NativeUprightImageMaker(),
    cropper: const IsolatePageCropper(),
    enhancer: const IsolateLightEnhancer(),
    lightMeter: FileLightMeter(
      maker: NativeUprightImageMaker(),
      workStore: workStore,
    ),
  );
}

class _NoopWorkStore implements OcrWorkStore {
  const _NoopWorkStore();

  @override
  Future<String> newImagePath() async => '';

  @override
  Future<void> delete(String path) async {}

  @override
  Future<int?> sizeOf(String path) async => null;

  @override
  Future<void> purgeAll() async {}
}

class _NoHeaderReader implements ImageHeaderReader {
  const _NoHeaderReader();

  @override
  Future<ImageHeader?> read(String path) async => null;
}

class _NoMaker implements UprightImageMaker {
  const _NoMaker();

  @override
  Future<UprightPixels> make({
    required String source,
    required String target,
    required int maxSide,
    required int jpegQuality,
  }) async => throw const UprightImageException('failed');
}
