import 'package:flutter_test/flutter_test.dart';
import 'package:image_spike/src/eval/text_metrics.dart';

void main() {
  test('levenshtein', () {
    expect(levenshtein('', ''), 0);
    expect(levenshtein('abc', ''), 3);
    expect(levenshtein('kitten', 'sitting'), 3);
    expect(levenshtein('Ψωμί', 'Ψωμι'), 1);
  });

  group('characterErrorRate', () {
    test('identical text is 0, whitespace layout does not count', () {
      expect(characterErrorRate('a b\nc', 'a  b c'), 0);
    });
    test('one wrong character in ten', () {
      expect(
        characterErrorRate('abcdeXghij', 'abcdefghij'),
        closeTo(0.1, 1e-9),
      );
    });
    test('missing text counts fully', () {
      expect(characterErrorRate('', 'abcd'), 1);
    });
  });

  group('wordRecall', () {
    test('multiset: a repeated word is needed twice', () {
      expect(wordRecall('a b', 'a a b'), closeTo(2 / 3, 1e-9));
      expect(wordRecall('a a b', 'a a b'), 1);
    });
    test('exact match only', () {
      expect(wordRecall('Ψωμί 1,45', 'Ψωμι 1,45'), 0.5);
    });
  });

  test('keyTokenRecall ignores case', () {
    expect(
      keyTokenRecall('Total 45,90 EUR', ['total', '45,90', 'iban']),
      closeTo(2 / 3, 1e-9),
    );
  });

  group('readingOrder', () {
    final known = [
      'first line of text',
      'second line here',
      'third and last line',
    ];
    test('right order scores 1', () {
      final r = readingOrder([
        'first line of text',
        'second line here',
        'third and last line',
      ], known);
      expect(r.score, 1);
      expect(r.matched, 3);
    });
    test('a label paired with the wrong place scores below 1', () {
      final r = readingOrder([
        'second line here',
        'first line of text',
        'third and last line',
      ], known);
      expect(r.score, closeTo(0.5, 1e-9));
    });
    test('pieces of one line count once, unmatched lines are skipped', () {
      final r = readingOrder([
        'first line',
        'of text',
        'zzzz qqqq',
        'second line here',
      ], known);
      expect(r.matched, 3);
      expect(r.score, 1);
    });
  });

  group('pairingAccuracy', () {
    const pairs = [('Milk 1L', '1,39'), ('DISCOUNT', '0,00'), ('NET', '38,39')];
    test('each label followed by its value scores 1', () {
      final r = pairingAccuracy('Milk 1L 1,39 DISCOUNT 0,00 NET 38,39', pairs);
      expect(r.accuracy, 1);
      expect(r.wrong, 0);
    });
    test('the failure of the real receipt: NET gets the discount value', () {
      final r = pairingAccuracy('Milk 1L 1,39 DISCOUNT NET 0,00 38,39', pairs);
      expect(r.wrong, 2);
      expect(r.accuracy, closeTo(1 / 3, 1e-9));
    });
    test('a missing label counts as wrong', () {
      expect(pairingAccuracy('Milk 1L 1,39', pairs).wrong, 2);
    });
  });
}
