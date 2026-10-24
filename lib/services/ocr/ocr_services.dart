import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/ocr/ocr_language_pack_registry.dart';
import '../../domain/ports/image_header_reader.dart';
import '../../domain/ports/ocr_engine.dart';
import '../../domain/ports/ocr_work_store.dart';
import '../../domain/ports/upright_image_maker.dart';
import '../image/dart_upright_image_maker.dart';
import '../image/file_image_header_reader.dart';
import '../image/io_ocr_work_store.dart';
import '../image/native_upright_image_maker.dart';
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
  });

  /// No OCR: the default of the container, so tests never load a model, touch
  /// the disk or call a native channel by accident.
  const OcrServices.unsupported()
    : engine = const UnsupportedOcrEngine(),
      workStore = const _NoopWorkStore(),
      headerReader = const _NoHeaderReader(),
      dartMaker = const _NoMaker(),
      nativeMaker = const _NoMaker();

  final OcrEngine engine;
  final OcrWorkStore workStore;
  final ImageHeaderReader headerReader;
  final UprightImageMaker dartMaker;
  final UprightImageMaker nativeMaker;
}

Future<OcrServices> createPlatformOcrServices({
  required OcrLanguagePackRegistry registry,
  required AppLogger logger,
}) async {
  if (!Platform.isAndroid) return const OcrServices.unsupported();
  final cache = await getTemporaryDirectory();
  final support = await getApplicationSupportDirectory();
  final sep = Platform.pathSeparator;
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
    workStore: IoOcrWorkStore(Directory('${cache.path}${sep}ocr_work')),
    headerReader: const FileImageHeaderReader(),
    dartMaker: const DartUprightImageMaker(),
    nativeMaker: NativeUprightImageMaker(),
  );
}

class _NoopWorkStore implements OcrWorkStore {
  const _NoopWorkStore();

  @override
  Future<String> newImagePath() async => '';

  @override
  Future<void> delete(String path) async {}

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
