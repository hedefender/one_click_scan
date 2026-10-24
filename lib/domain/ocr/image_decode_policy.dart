import 'ocr_config.dart';

/// How a photo of a given size may be turned into the working copy.
enum ImageDecodePlan {
  /// Small: `package:image` in a background isolate.
  dartIsolate,

  /// Large: native decode, down-scaled while decoding.
  native,

  /// Above the limit: refused, nothing is decoded.
  tooLarge,
}

/// Decides from the header size ([megapixels] of the stored image). The limits
/// are inclusive: exactly [OcrConfig.dartDecodeMaxMegapixels] is still Dart,
/// exactly [OcrConfig.maxMegapixels] is still accepted. A decode never runs on
/// the UI isolate, whatever the plan.
ImageDecodePlan planImageDecode(double megapixels) {
  if (megapixels > OcrConfig.maxMegapixels) return ImageDecodePlan.tooLarge;
  if (megapixels <= OcrConfig.dartDecodeMaxMegapixels) {
    return ImageDecodePlan.dartIsolate;
  }
  return ImageDecodePlan.native;
}
