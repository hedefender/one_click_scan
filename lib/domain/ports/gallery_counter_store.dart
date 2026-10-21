/// Remembers the daily number of the Gallery copies (ADR-009).
abstract interface class GalleryCounterStore {
  /// The number the next Gallery copy of [date] (`YYYY-MM-DD`) gets: one more
  /// than the last used number of that date, or 1 on a new date.
  int nextNumber(String date);

  /// Records that [number] was used on [date]. Called only after the copy was
  /// saved, so a failure leaves no gap.
  Future<void> markUsed(String date, int number);
}
