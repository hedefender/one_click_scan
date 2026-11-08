/// Cache files of the OCR: the upright working copies.
abstract interface class OcrWorkStore {
  /// A new unique file path for a working copy (its folder exists).
  Future<String> newImagePath();

  Future<void> delete(String path);

  /// Size of the file in bytes, or null when it cannot be read. The picture of
  /// a working copy is what goes into the PDF, so its size is the size the
  /// page will have there (ADR-032).
  Future<int?> sizeOf(String path);

  /// Removes everything (leftovers of a killed run, at start-up).
  Future<void> purgeAll();
}
