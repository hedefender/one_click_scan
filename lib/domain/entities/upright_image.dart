import 'package:equatable/equatable.dart';

/// The working copy the OCR and the PDF read (after the crop of Phase 6.1 it
/// is the straightened page, ADR-029): EXIF orientation
/// applied, long side at most `OcrConfig.workingSide`, stored in the app cache.
///
/// [width] and [height] are the pixels of that file as decoded. They are never
/// taken from the EXIF size tags (on Xiaomi camera files these are wrong).
class UprightImage extends Equatable {
  const UprightImage({
    required this.path,
    required this.width,
    required this.height,
    required this.sourceWidth,
    required this.sourceHeight,
    this.focalLength35mm,
  });

  final String path;
  final int width;
  final int height;

  /// Pixels of the original file as stored (before orientation and scaling),
  /// from the file header. The capture resolution of the camera.
  final int sourceWidth;
  final int sourceHeight;

  /// EXIF 35 mm equivalent focal length of the original photo (null when it
  /// had none). The working copy has no EXIF, so it travels here.
  final int? focalLength35mm;

  double get sourceMegapixels => sourceWidth * sourceHeight / 1e6;

  @override
  List<Object?> get props => [
    path,
    width,
    height,
    sourceWidth,
    sourceHeight,
    focalLength35mm,
  ];
}
