import 'dart:math' as math;
import 'dart:typed_data';

import '../../../domain/ocr/char_boxes.dart';

/// The CTC character table: index 0 is the blank, then the dictionary lines,
/// then the space (the model has one more class than the file has lines).
List<String> parseDictionary(String text) {
  final chars = text.split('\n').map((l) => l.replaceAll('\r', '')).toList();
  if (chars.isNotEmpty && chars.last.isEmpty) chars.removeLast();
  return ['', ...chars, ' '];
}

/// What greedy CTC decoding returns: the text, its confidence and where each
/// emitted character sits along the box.
class CtcDecoded {
  const CtcDecoded(this.text, this.confidence, this.spans);

  final String text;

  /// Mean probability of the emitted characters (0 when there are none).
  final double confidence;

  /// One span per emitted character (the characters joined are [text]).
  final List<CharSpan> spans;
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
  final decoded = ctcGreedyWithSpans(flat, item, t, classes, steps, dict);
  return (decoded.text, decoded.confidence);
}

/// [ctcGreedy] that also reports, per emitted character, the place it was
/// emitted at (the time steps of its run), as a [CharSpan] along the box.
CtcDecoded ctcGreedyWithSpans(
  Float32List flat,
  int item,
  int t,
  int classes,
  int steps,
  List<String> dict,
) {
  final buffer = StringBuffer();
  final characters = <String>[];
  final firstStep = <int>[];
  final lastStep = <int>[];
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
      if (best < dict.length) {
        buffer.write(dict[best]);
        characters.add(dict[best]);
        firstStep.add(s);
        lastStep.add(s);
      }
      confSum += bestP;
      confCount++;
    } else if (best != 0 && best == last && best < dict.length) {
      // The same character goes on: its run grows.
      lastStep[lastStep.length - 1] = s;
    }
    last = best;
  }
  return CtcDecoded(
    buffer.toString(),
    confCount == 0 ? 0.0 : confSum / confCount,
    charSpans(characters, firstStep, lastStep, steps),
  );
}

/// Turns the runs of the emitted characters into extents along the box, as
/// fractions of its length. The centre of a character is the middle of its
/// run; the edge between two characters is the midpoint of their centres; the
/// outer edges continue half a gap beyond the first and the last centre.
List<CharSpan> charSpans(
  List<String> characters,
  List<int> firstStep,
  List<int> lastStep,
  int steps,
) {
  final n = characters.length;
  if (n == 0 || steps <= 0) return const [];
  final centres = [
    for (var i = 0; i < n; i++) (firstStep[i] + lastStep[i] + 1) / 2 / steps,
  ];
  final spans = <CharSpan>[];
  for (var i = 0; i < n; i++) {
    double left, right;
    if (n == 1) {
      left = firstStep[i] / steps;
      right = (lastStep[i] + 1) / steps;
    } else {
      left = i == 0
          ? centres[0] - (centres[1] - centres[0]) / 2
          : (centres[i - 1] + centres[i]) / 2;
      right = i == n - 1
          ? centres[i] + (centres[i] - centres[i - 1]) / 2
          : (centres[i] + centres[i + 1]) / 2;
    }
    spans.add(
      CharSpan(characters[i], math.max(0.0, left), math.min(1.0, right)),
    );
  }
  return spans;
}
