import 'package:equatable/equatable.dart';

/// What happened with the optional copy in the phone Gallery.
enum GalleryCopyStatus {
  /// The Gallery switch was off, so no copy was attempted.
  notRequested,
  saved,
  failed,
}

/// One image written to the user's folder.
class StoredPicture extends Equatable {
  const StoredPicture({
    required this.fileName,
    required this.sourcePath,
    this.gallery = GalleryCopyStatus.notRequested,
    this.uri,
    this.galleryUri,
  });

  /// File name inside `./pictures/` (for example `2026-10-21_19-05-12_1.jpg`).
  final String fileName;

  /// Temporary cache file the picture was copied from. Only used to show a
  /// thumbnail until the result screen is left; may no longer exist.
  final String sourcePath;

  final GalleryCopyStatus gallery;

  /// Document URI of the file in `./pictures`. What a discard deletes by: a
  /// file is never found again by its name or its folder (ADR-027).
  final String? uri;

  /// URI of the Gallery copy, when one was saved.
  final String? galleryUri;

  StoredPicture copyWith({GalleryCopyStatus? gallery, String? galleryUri}) {
    return StoredPicture(
      fileName: fileName,
      sourcePath: sourcePath,
      gallery: gallery ?? this.gallery,
      uri: uri,
      galleryUri: galleryUri ?? this.galleryUri,
    );
  }

  @override
  List<Object?> get props => [fileName, sourcePath, gallery, uri, galleryUri];
}

/// Result of storing a whole scan.
class StoredScan extends Equatable {
  const StoredScan({required this.stem, required this.pictures});

  /// Shared name stem of the scan, `YYYY-MM-DD_HH-MM-SS` (with `-2`, `-3`...
  /// on a collision).
  final String stem;
  final List<StoredPicture> pictures;

  /// The scan itself is stored; only the Gallery copy of some pictures failed.
  bool get hasGalleryFailures =>
      pictures.any((picture) => picture.gallery == GalleryCopyStatus.failed);

  @override
  List<Object?> get props => [stem, pictures];
}
