import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;

import '../../domain/ports/upright_image_maker.dart';

/// Working copy with `package:image`, entirely in a background isolate (the UI
/// isolate is never involved). For small photos only; the policy in
/// `planImageDecode` sends larger ones to the native maker.
///
/// The JPEG decoder of `package:image` applies the EXIF orientation while it
/// decodes and clears the tag (an invalid value such as 0 means no rotation),
/// so no second rotation happens here.
class DartUprightImageMaker implements UprightImageMaker {
  const DartUprightImageMaker();

  @override
  Future<UprightPixels> make({
    required String source,
    required String target,
    required int maxSide,
    required int jpegQuality,
  }) async {
    try {
      final (w, h) = await Isolate.run(
        () => makeUprightSync(source, target, maxSide, jpegQuality),
      );
      return UprightPixels(width: w, height: h);
    } on UprightImageException {
      rethrow;
    } on OutOfMemoryError {
      throw const UprightImageException('outOfMemory');
    } catch (_) {
      throw const UprightImageException('failed');
    }
  }
}

/// The work of [DartUprightImageMaker], synchronous so a test can call it
/// directly. Returns the pixel size of the written file.
(int, int) makeUprightSync(
  String source,
  String target,
  int maxSide,
  int jpegQuality,
) {
  final bytes = File(source).readAsBytesSync();
  var image = img.decodeImage(bytes);
  if (image == null) throw const UprightImageException('unreadable');
  if (image.numChannels != 3) image = image.convert(numChannels: 3);
  final longSide = image.width > image.height ? image.width : image.height;
  if (longSide > maxSide) {
    final scale = maxSide / longSide;
    image = img.copyResize(
      image,
      width: (image.width * scale).round().clamp(1, maxSide),
      height: (image.height * scale).round().clamp(1, maxSide),
      interpolation: img.Interpolation.average,
    );
  }
  File(target).writeAsBytesSync(img.encodeJpg(image, quality: jpegQuality));
  return (image.width, image.height);
}
