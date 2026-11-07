import 'dart:io';

import '../../domain/lighting/light_metric.dart';
import '../../domain/lighting/lighting_config.dart';
import '../../domain/ports/light_meter.dart';
import '../../domain/ports/ocr_work_store.dart';
import '../../domain/ports/upright_image_maker.dart';

import 'package:flutter/foundation.dart' show compute;

import 'light_jobs.dart';

/// [LightMeter] for a shot (a 12 MP JPEG): a small copy is made by the native
/// maker (`inSampleSize`, the full picture is never decoded), the metric is
/// taken from it in a background isolate, and the small copy is deleted at
/// once, so nothing of the page stays in the cache (ADR-018). Never throws.
class FileLightMeter implements LightMeter {
  const FileLightMeter({required this.maker, required this.workStore});

  final UprightImageMaker maker;
  final OcrWorkStore workStore;

  @override
  Future<LightMetric?> measureFile(String path) async {
    String? small;
    try {
      small = await workStore.newImagePath();
      await maker.make(
        source: path,
        target: small,
        maxSide: LightingConfig.thumbnailSide,
        jpegQuality: 80,
      );
      return await compute(measureJpegSync, small);
    } catch (_) {
      return null;
    } finally {
      if (small != null) {
        try {
          final file = File(small);
          if (await file.exists()) await file.delete();
        } on FileSystemException {
          // The cache is purged at the next start-up anyway.
        }
      }
    }
  }
}
