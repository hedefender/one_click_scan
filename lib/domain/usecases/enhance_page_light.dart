import '../entities/upright_image.dart';
import '../ocr/ocr_cancellation.dart';
import '../ocr/ocr_config.dart';
import '../ports/light_enhancer.dart';
import '../ports/ocr_work_store.dart';

/// Makes the light-corrected copy of the working picture of a page. The old
/// working copy is NOT touched here: the caller keeps the version that reads
/// more words and deletes the other (`chooseByWords`).
class EnhancePageLight {
  const EnhancePageLight({required this.enhancer, required this.workStore});

  /// Longest time the correction may take (the pictures are about 2000 px).
  static const timeout = Duration(seconds: 20);

  final LightEnhancer enhancer;
  final OcrWorkStore workStore;

  /// Null when the correction could not be made. Never throws.
  Future<UprightImage?> call(
    UprightImage image, {
    OcrCancellation? cancellation,
  }) async {
    String? target;
    try {
      target = await workStore.newImagePath();
      final done = await enhancer.enhance(
        source: image.path,
        target: target,
        jpegQuality: OcrConfig.workingJpegQuality,
        timeout: timeout,
        cancellation: cancellation,
      );
      if (!done) {
        await _delete(target);
        return null;
      }
      return UprightImage(
        path: target,
        width: image.width,
        height: image.height,
        sourceWidth: image.sourceWidth,
        sourceHeight: image.sourceHeight,
        focalLength35mm: image.focalLength35mm,
      );
    } catch (_) {
      if (target != null) await _delete(target);
      return null;
    }
  }

  Future<void> _delete(String path) async {
    try {
      await workStore.delete(path);
    } catch (_) {
      // The cache is purged at the next start-up anyway.
    }
  }
}
