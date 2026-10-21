/// Pure naming rule for the Gallery copies (ADR-009): `scan_YYYY-MM-DD_NN.jpg`.
///
/// The date is the device date, and `NN` is the daily counter, two digits with
/// a leading zero and growing past 99. The clock is injected so tests control
/// the date; the number comes from a `GalleryCounterStore`.
class GalleryNaming {
  const GalleryNaming(this._now);

  final DateTime Function() _now;

  /// Today's device date as `YYYY-MM-DD`. It is also the key of the counter:
  /// when it changes, the numbering starts again at 1.
  String today() {
    final now = _now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year.toString().padLeft(4, '0')}-${two(now.month)}-'
        '${two(now.day)}';
  }

  /// `scan_<date>_<number>.jpg`, [number] starting at 1.
  String fileName(String date, int number) {
    return 'scan_${date}_${number.toString().padLeft(2, '0')}.jpg';
  }
}
