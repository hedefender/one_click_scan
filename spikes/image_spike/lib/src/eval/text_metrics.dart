/// Text comparison for the OCR gain. The known text is the invented text of a
/// synthetic page, so all numbers are against ground truth.
library;

String normalizeText(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

List<String> wordsOf(String s) {
  final n = normalizeText(s);
  return n.isEmpty ? const [] : n.split(' ');
}

/// Edit distance between two strings (by code point), two-row dynamic
/// programming.
int levenshtein(String a, String b) {
  final x = a.runes.toList(), y = b.runes.toList();
  if (x.isEmpty) return y.length;
  if (y.isEmpty) return x.length;
  var prev = List<int>.generate(y.length + 1, (j) => j);
  var cur = List<int>.filled(y.length + 1, 0);
  for (var i = 1; i <= x.length; i++) {
    cur[0] = i;
    for (var j = 1; j <= y.length; j++) {
      final cost = x[i - 1] == y[j - 1] ? 0 : 1;
      final del = prev[j] + 1, ins = cur[j - 1] + 1, sub = prev[j - 1] + cost;
      var m = del < ins ? del : ins;
      if (sub < m) m = sub;
      cur[j] = m;
    }
    final t = prev;
    prev = cur;
    cur = t;
  }
  return prev[y.length];
}

/// Character error rate: edit distance over the length of the known text, on
/// text with whitespace collapsed (a split or joined line costs nothing).
double characterErrorRate(String recognized, String known) {
  final k = normalizeText(known);
  if (k.isEmpty) return 0;
  return levenshtein(normalizeText(recognized), k) / k.runes.length;
}

/// Share of the known words (a word counts once per occurrence) that appear
/// among the recognised words, exactly.
double wordRecall(String recognized, String known) {
  final kw = wordsOf(known);
  if (kw.isEmpty) return 1;
  final pool = <String, int>{};
  for (final w in wordsOf(recognized)) {
    pool[w] = (pool[w] ?? 0) + 1;
  }
  var found = 0;
  for (final w in kw) {
    final n = pool[w] ?? 0;
    if (n > 0) {
      found++;
      pool[w] = n - 1;
    }
  }
  return found / kw.length;
}

/// Share of [tokens] that occur in [text] (case-insensitive).
double keyTokenRecall(String text, List<String> tokens) {
  if (tokens.isEmpty) return 1;
  final hay = normalizeText(text).toLowerCase();
  final found = tokens
      .where((t) => hay.contains(normalizeText(t).toLowerCase()))
      .length;
  return found / tokens.length;
}

Set<String> _bigrams(String s) {
  final t = normalizeText(s).toLowerCase().replaceAll(' ', '');
  final out = <String>{};
  for (var i = 0; i + 1 < t.length; i++) {
    out.add(t.substring(i, i + 2));
  }
  return out;
}

double _dice(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final inter = a.intersection(b).length;
  return 2 * inter / (a.length + b.length);
}

/// How well the reading order of the recognised lines follows the known lines.
/// Each recognised line is matched to the known line it resembles most (bigram
/// similarity at least 0.5); consecutive lines that match the same known line
/// are one. The score is the share of adjacent pairs that go forward
/// (1.0 = the order is right). [matched] is how many recognised lines found
/// a known line.
({double score, int matched, int pairs}) readingOrder(
  List<String> recognizedLines,
  List<String> knownLines,
) {
  final known = [for (final l in knownLines) _bigrams(l)];
  final seq = <int>[];
  var matched = 0;
  for (final line in recognizedLines) {
    final g = _bigrams(line);
    var best = -1;
    var bestScore = 0.0;
    for (var i = 0; i < known.length; i++) {
      final d = _dice(g, known[i]);
      if (d > bestScore) {
        bestScore = d;
        best = i;
      }
    }
    if (best >= 0 && bestScore >= 0.5) {
      matched++;
      if (seq.isEmpty || seq.last != best) seq.add(best);
    }
  }
  if (seq.length < 2) return (score: 1.0, matched: matched, pairs: 0);
  var forward = 0;
  for (var i = 1; i < seq.length; i++) {
    if (seq[i] > seq[i - 1]) forward++;
  }
  return (
    score: forward / (seq.length - 1),
    matched: matched,
    pairs: seq.length - 1,
  );
}

/// Label-and-value pairing: for each ([label], [value]) the share of pairs
/// where the first token that follows the label's last word in the recognised
/// text is the value. A label that gets the value of another line (or none)
/// counts as wrong; a label not found counts as wrong.
({double accuracy, int pairs, int wrong}) pairingAccuracy(
  String recognized,
  List<(String, String)> pairs,
) {
  final tokens = wordsOf(recognized);
  var right = 0;
  for (final (label, value) in pairs) {
    final lw = wordsOf(label);
    var ok = false;
    // Find the label as a run of tokens; look at the token right after it.
    for (var i = 0; i + lw.length < tokens.length && !ok; i++) {
      var match = true;
      for (var k = 0; k < lw.length; k++) {
        if (tokens[i + k] != lw[k]) {
          match = false;
          break;
        }
      }
      if (match && tokens[i + lw.length] == value) ok = true;
    }
    if (ok) right++;
  }
  return (
    accuracy: pairs.isEmpty ? 1.0 : right / pairs.length,
    pairs: pairs.length,
    wrong: pairs.length - right,
  );
}
