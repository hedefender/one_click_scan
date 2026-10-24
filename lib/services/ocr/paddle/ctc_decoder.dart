import 'dart:typed_data';

/// The CTC character table: index 0 is the blank, then the dictionary lines,
/// then the space (the model has one more class than the file has lines).
List<String> parseDictionary(String text) {
  final chars = text.split('\n').map((l) => l.replaceAll('\r', '')).toList();
  if (chars.isNotEmpty && chars.last.isEmpty) chars.removeLast();
  return ['', ...chars, ' '];
}

/// Greedy CTC decoding of item [item] of a `[B, T, C]` output, using only the
/// first [steps] time steps (the rest is padding). Repeats are merged and
/// blanks dropped. The confidence is the mean probability of the emitted
/// characters (0 when there are none).
///
/// Runs on typed lists in plain loops: the boxed-list version of the spike
/// took about 260 ms per page where this takes about 70 ms.
(String, double) ctcGreedy(
  Float32List flat,
  int item,
  int t,
  int classes,
  int steps,
  List<String> dict,
) {
  final buffer = StringBuffer();
  var last = 0;
  var confSum = 0.0, confCount = 0;
  final off = item * t * classes;
  for (var s = 0; s < steps; s++) {
    var best = 0;
    final base = off + s * classes;
    var bestP = flat[base];
    for (var c = 1; c < classes; c++) {
      final p = flat[base + c];
      if (p > bestP) {
        bestP = p;
        best = c;
      }
    }
    if (best != 0 && best != last) {
      if (best < dict.length) buffer.write(dict[best]);
      confSum += bestP;
      confCount++;
    }
    last = best;
  }
  return (buffer.toString(), confCount == 0 ? 0.0 : confSum / confCount);
}
