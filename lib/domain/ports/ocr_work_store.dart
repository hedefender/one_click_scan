/// Cache files of the OCR: the upright working copies.
abstract interface class OcrWorkStore {
  /// A new unique file path for a working copy (its folder exists).
  Future<String> newImagePath();

  Future<void> delete(String path);

  /// Removes everything (leftovers of a killed run, at start-up).
  Future<void> purgeAll();
}
