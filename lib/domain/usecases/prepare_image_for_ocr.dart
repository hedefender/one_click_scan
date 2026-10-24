import '../entities/ocr_outcome.dart';
import '../entities/upright_image.dart';
import '../ocr/image_decode_policy.dart';
import '../ocr/ocr_config.dart';
import '../ports/image_header_reader.dart';
import '../ports/ocr_work_store.dart';
import '../ports/upright_image_maker.dart';

/// The photo could not become a working copy.
class ImagePreparationException implements Exception {
  const ImagePreparationException(this.reason);

  final OcrFailureReason reason;

  @override
  String toString() => 'ImagePreparationException(${reason.name})';
}

/// Makes the upright working copy of a captured photo: reads the header first
/// (nothing is decoded above the size limit), applies the EXIF orientation,
/// scales to at most [OcrConfig.workingSide] and stores the result in the
/// cache. The size of the result is that of the decoded pixels.
class PrepareImageForOcr {
  const PrepareImageForOcr({
    required this.headerReader,
    required this.dartMaker,
    required this.nativeMaker,
    required this.workStore,
  });

  final ImageHeaderReader headerReader;
  final UprightImageMaker dartMaker;
  final UprightImageMaker nativeMaker;
  final OcrWorkStore workStore;

  /// Throws [ImagePreparationException].
  Future<UprightImage> call(String sourcePath) async {
    final header = await headerReader.read(sourcePath);
    if (header == null) {
      throw const ImagePreparationException(OcrFailureReason.imageUnreadable);
    }
    final maker = switch (planImageDecode(header.megapixels)) {
      ImageDecodePlan.tooLarge => throw const ImagePreparationException(
        OcrFailureReason.imageTooLarge,
      ),
      ImageDecodePlan.dartIsolate => dartMaker,
      ImageDecodePlan.native => nativeMaker,
    };

    final target = await workStore.newImagePath();
    try {
      final pixels = await maker.make(
        source: sourcePath,
        target: target,
        maxSide: OcrConfig.workingSide,
        jpegQuality: OcrConfig.workingJpegQuality,
      );
      return UprightImage(
        path: target,
        width: pixels.width,
        height: pixels.height,
        sourceWidth: header.width,
        sourceHeight: header.height,
      );
    } on UprightImageException catch (error) {
      await workStore.delete(target);
      throw ImagePreparationException(switch (error.code) {
        'unreadable' => OcrFailureReason.imageUnreadable,
        _ => OcrFailureReason.engineError,
      });
    } catch (_) {
      await workStore.delete(target);
      throw const ImagePreparationException(OcrFailureReason.engineError);
    }
  }
}
