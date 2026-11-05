import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../ocr_copy/core/logging/app_logger.dart';
import '../ocr_copy/domain/entities/ocr_outcome.dart';
import '../ocr_copy/domain/entities/upright_image.dart';
import '../ocr_copy/domain/ocr/ocr_language_pack_registry.dart';
import '../ocr_copy/services/ocr/ocr_model_store.dart';
import '../ocr_copy/services/ocr/paddle_ocr_engine.dart';

/// Only numbers of a reading ever leave this class (never the text).
class OcrNumbers {
  const OcrNumbers({required this.words, required this.ms});

  final int words;
  final int ms;
}

/// The real OCR engine of the app (a copy, see tool/sync_ocr_code.sh) on a
/// picture file.
class SpikeOcr {
  SpikeOcr._(this._engine, this._cache);

  final PaddleOcrEngine _engine;
  final Directory _cache;
  var _counter = 0;

  static Future<SpikeOcr> create() async {
    final cache = await getTemporaryDirectory();
    final support = await getApplicationSupportDirectory();
    final registry = OcrLanguagePackRegistry.standard;
    final engine = PaddleOcrEngine(
      registry: registry,
      logger: const DebugAppLogger(),
      models: OcrModelStore(
        directory: Directory('${support.path}/ocr_models'),
        loadAsset: rootBundle.load,
        registry: registry,
      ),
    );
    return SpikeOcr._(engine, cache);
  }

  /// Writes [jpg] to the cache and returns its path (the caller deletes it).
  File writeTemp(Uint8List jpg) =>
      File('${_cache.path}/spike_${_counter++}.jpg')..writeAsBytesSync(jpg);

  Future<OcrNumbers> readFile(
    File file, {
    required int width,
    required int height,
    String pack = 'greek',
  }) async {
    final sw = Stopwatch()..start();
    final outcome = await _engine.recognize(
      UprightImage(
        path: file.path,
        width: width,
        height: height,
        sourceWidth: width,
        sourceHeight: height,
      ),
      packId: pack,
      timeout: const Duration(seconds: 180),
    );
    final ms = sw.elapsedMilliseconds;
    var words = 0;
    if (outcome is OcrSuccess) {
      for (final l in outcome.result.lines) {
        if (!l.filtered) {
          words += l.text
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .length;
        }
      }
    }
    return OcrNumbers(words: words, ms: ms);
  }

  Future<void> dispose() => _engine.dispose();
}
