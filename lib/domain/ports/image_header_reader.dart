/// What the header of an image file says, read without decoding it.
class ImageHeader {
  const ImageHeader({
    required this.width,
    required this.height,
    required this.orientation,
  });

  /// Pixels of the stored image (not the EXIF size tags).
  final int width;
  final int height;

  /// EXIF orientation 1..8; 1 when the tag is missing or invalid (0, 9...).
  final int orientation;

  double get megapixels => width * height / 1e6;
}

abstract interface class ImageHeaderReader {
  /// Null when the file is missing or not a JPEG or PNG.
  Future<ImageHeader?> read(String path);
}
