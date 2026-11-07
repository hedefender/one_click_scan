/// What the header of an image file says, read without decoding it.
class ImageHeader {
  const ImageHeader({
    required this.width,
    required this.height,
    required this.orientation,
    this.focalLength35mm,
  });

  /// Pixels of the stored image (not the EXIF size tags).
  final int width;
  final int height;

  /// EXIF orientation 1..8; 1 when the tag is missing or invalid (0, 9...).
  final int orientation;

  /// EXIF 35 mm equivalent focal length in millimetres; null when the photo
  /// has none. Used to straighten a tilted page in its true proportions.
  final int? focalLength35mm;

  double get megapixels => width * height / 1e6;
}

abstract interface class ImageHeaderReader {
  /// Null when the file is missing or not a JPEG or PNG.
  Future<ImageHeader?> read(String path);
}
