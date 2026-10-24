/// Pixels of a written working copy.
class UprightPixels {
  const UprightPixels({required this.width, required this.height});

  final int width;
  final int height;
}

/// Thrown by a maker when the image cannot be turned into a working copy.
class UprightImageException implements Exception {
  const UprightImageException(this.code);

  /// `unreadable`, `outOfMemory` or `failed`. Never user content.
  final String code;

  @override
  String toString() => 'UprightImageException($code)';
}

/// Decodes [source], applies the EXIF orientation, scales so the long side is
/// at most [maxSide] and writes a JPEG to [target]. Two implementations: Dart
/// in a background isolate for small images, native for the large ones.
abstract interface class UprightImageMaker {
  Future<UprightPixels> make({
    required String source,
    required String target,
    required int maxSide,
    required int jpegQuality,
  });
}
