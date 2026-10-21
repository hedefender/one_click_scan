/// Pure naming rules for stored scans (ADR-005).
///
/// The clock is injected so tests control the time.
class ScanNaming {
  const ScanNaming(this._now);

  final DateTime Function() _now;

  static final RegExp _storedName = RegExp(
    r'^(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}(?:-\d+)?)(?:_\d+)?\.(?:jpg|pdf)$',
  );

  /// Device time as `YYYY-MM-DD_HH-MM-SS`, with `-2`, `-3`... when the stem
  /// is already taken (two scans in the same second).
  String nextStem(Set<String> existingStems) {
    final base = _format(_now());
    if (!existingStems.contains(base)) return base;
    var suffix = 2;
    while (existingStems.contains('$base-$suffix')) {
      suffix++;
    }
    return '$base-$suffix';
  }

  /// `<stem>_<n>.jpg`, with [pageNumber] starting at 1.
  String pictureName(String stem, int pageNumber) {
    return '${stem}_$pageNumber.jpg';
  }

  /// Stems already used by the given file names (`<stem>_<n>.jpg` or
  /// `<stem>.pdf`). Other files are ignored.
  Set<String> existingStems(Iterable<String> fileNames) {
    return <String>{
      for (final name in fileNames)
        if (_storedName.firstMatch(name) case final match?) match.group(1)!,
    };
  }

  static String _format(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year.toString().padLeft(4, '0')}-${two(time.month)}-'
        '${two(time.day)}_${two(time.hour)}-${two(time.minute)}-'
        '${two(time.second)}';
  }
}
