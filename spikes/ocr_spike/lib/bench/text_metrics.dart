import 'dart:math' as math;
import 'dart:typed_data';

const microSign = 'µ'; // µ
const greekMu = 'μ'; // μ

/// Whitespace runs -> one space, trimmed. Nothing else is touched.
String collapse(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Same as [collapse] plus µ/μ unified (used for the key-token search only).
String forSearch(String s) => collapse(s).replaceAll(microSign, greekMu);

/// Levenshtein distance with the per-reference-character match flags of one
/// optimal alignment (true = this reference character was reproduced).
class Alignment {
  Alignment(this.distance, this.matched);
  final int distance;
  final List<bool> matched;
}

Alignment align(List<String> ref, List<String> hyp) {
  final n = ref.length, m = hyp.length;
  final d = List<Int32List>.generate(n + 1, (_) => Int32List(m + 1));
  for (var i = 0; i <= n; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= m; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final cost = ref[i - 1] == hyp[j - 1] ? 0 : 1;
      d[i][j] = math.min(
        math.min(d[i - 1][j] + 1, d[i][j - 1] + 1),
        d[i - 1][j - 1] + cost,
      );
    }
  }
  final matched = List<bool>.filled(n, false);
  var i = n, j = m;
  while (i > 0 && j > 0) {
    final cost = ref[i - 1] == hyp[j - 1] ? 0 : 1;
    if (d[i][j] == d[i - 1][j - 1] + cost) {
      matched[i - 1] = cost == 0;
      i--;
      j--;
    } else if (d[i][j] == d[i - 1][j] + 1) {
      i--;
    } else {
      j--;
    }
  }
  return Alignment(d[n][m], matched);
}

List<String> chars(String s) => s.runes.map(String.fromCharCode).toList();

class TextScore {
  TextScore({
    required this.charErrors,
    required this.charTotal,
    required this.wordErrors,
    required this.wordTotal,
    required this.bagHits,
    required this.bagTotal,
    required this.categories,
    required this.sortedCharErrors,
    required this.sortedCharTotal,
  });

  /// Characters errors after sorting the words of both texts: layout and
  /// reading order no longer count (tables, columns).
  final int sortedCharErrors, sortedCharTotal;
  double get sortedCer =>
      sortedCharTotal == 0 ? 0 : sortedCharErrors / sortedCharTotal;

  final int charErrors, charTotal, wordErrors, wordTotal, bagHits, bagTotal;

  /// category -> (kept, total) over the reference characters.
  final Map<String, (int, int)> categories;

  double get cer => charTotal == 0 ? 0 : charErrors / charTotal;
  double get wer => wordTotal == 0 ? 0 : wordErrors / wordTotal;
  double get bagRecall => bagTotal == 0 ? 1 : bagHits / bagTotal;
}

const _accentedLower = 'άέήίόύώΐΰ';
const _accentedUpper = 'ΆΈΉΊΌΎΏ';
const _greekUpper = 'ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ';

String? _category(String c) {
  if (_accentedLower.contains(c)) return 'accented_lower';
  if (_accentedUpper.contains(c)) return 'accented_upper';
  if (c == 'ς') return 'final_sigma';
  if (_greekUpper.contains(c)) return 'greek_upper';
  if (RegExp(r'[α-ω]').hasMatch(c)) return 'greek_lower';
  if (RegExp(r'[A-Za-z]').hasMatch(c)) return 'latin';
  if (RegExp(r'[0-9]').hasMatch(c)) return 'digit';
  if (c == greekMu) return 'mu_greek';
  if (c == microSign) return 'mu_micro';
  return null;
}

TextScore score(String reference, String hypothesis) {
  final ref = collapse(reference), hyp = collapse(hypothesis);
  final rc = chars(ref), hc = chars(hyp);
  final a = align(rc, hc);

  final rw = ref.isEmpty ? <String>[] : ref.split(' ');
  final hw = hyp.isEmpty ? <String>[] : hyp.split(' ');
  final wordAlign = align(rw, hw);

  final bag = <String, int>{};
  for (final w in hw) {
    bag[w] = (bag[w] ?? 0) + 1;
  }
  var hits = 0;
  for (final w in rw) {
    final left = bag[w] ?? 0;
    if (left > 0) {
      hits++;
      bag[w] = left - 1;
    }
  }

  final cats = <String, (int, int)>{};
  for (var i = 0; i < rc.length; i++) {
    final cat = _category(rc[i]);
    if (cat == null) continue;
    final (kept, total) = cats[cat] ?? (0, 0);
    cats[cat] = (kept + (a.matched[i] ? 1 : 0), total + 1);
  }
  final sr = ([...rw]..sort()).join(' ');
  final sh = ([...hw]..sort()).join(' ');
  final sa = align(chars(sr), chars(sh));
  return TextScore(
    sortedCharErrors: sa.distance,
    sortedCharTotal: sr.runes.length,
    charErrors: a.distance,
    charTotal: rc.length,
    wordErrors: wordAlign.distance,
    wordTotal: rw.length,
    bagHits: hits,
    bagTotal: rw.length,
    categories: cats,
  );
}

/// Counts of the two mu characters in a text.
(int greek, int micro) muCounts(String s) =>
    (greekMu.allMatches(s).length, microSign.allMatches(s).length);

const _fold = <String, String>{
  'Α': 'A',
  'Β': 'B',
  'Ε': 'E',
  'Ζ': 'Z',
  'Η': 'H',
  'Ι': 'I',
  'Κ': 'K',
  'Μ': 'M',
  'Ν': 'N',
  'Ο': 'O',
  'Ρ': 'P',
  'Τ': 'T',
  'Υ': 'Y',
  'Χ': 'X',
  'α': 'a',
  'ι': 'i',
  'κ': 'k',
  'ν': 'v',
  'ο': 'o',
  'ρ': 'p',
  'υ': 'u',
  'χ': 'x',
  microSign: greekMu,
};

/// Greek and Latin look-alike letters unified, plus µ/μ (for the "folded"
/// key search: tells apart a wrong script from a wrong character).
String fold(String s) {
  final b = StringBuffer();
  for (final r in forSearch(s).runes) {
    final c = String.fromCharCode(r);
    b.write(_fold[c] ?? c);
  }
  return b.toString();
}

bool containsFolded(String text, String value) =>
    fold(text).contains(fold(value));

/// True when [value] (whitespace/µμ-normalised) occurs in [text].
bool containsValue(String text, String value) =>
    forSearch(text).contains(forSearch(value));
