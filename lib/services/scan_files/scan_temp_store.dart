/// The app-cache area where captured pages wait until the scan is stored.
abstract interface class ScanTempStore {
  /// Deletes the given temporary files. Missing files are ignored.
  Future<void> delete(Iterable<String> paths);

  /// Deletes everything left from earlier runs (killed or crashed mid-scan).
  /// Called once at start-up, when no scan can be in progress.
  Future<void> purgeAll();
}
