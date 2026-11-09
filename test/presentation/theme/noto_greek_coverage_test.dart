import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Phase 6.4 (DESIGN_SPEC 3.6): every Greek letter with a tone is in the three
/// Noto Sans files of the app, so no fallback font is ever needed for them.
/// The test reads the `cmap` table of each TrueType file.
Set<int> readCodePoints(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final tables = data.getUint16(4);
  var cmapOffset = -1;
  for (var i = 0; i < tables; i++) {
    final record = 12 + i * 16;
    final tag = String.fromCharCodes(bytes.sublist(record, record + 4));
    if (tag == 'cmap') cmapOffset = data.getUint32(record + 8);
  }
  if (cmapOffset < 0) throw StateError('no cmap table');

  final points = <int>{};
  final subtables = data.getUint16(cmapOffset + 2);
  for (var i = 0; i < subtables; i++) {
    final record = cmapOffset + 4 + i * 8;
    final offset = cmapOffset + data.getUint32(record + 4);
    final format = data.getUint16(offset);
    if (format == 4) {
      final segX2 = data.getUint16(offset + 6);
      final ends = offset + 14;
      final starts = ends + segX2 + 2;
      for (var s = 0; s < segX2 ~/ 2; s++) {
        final end = data.getUint16(ends + s * 2);
        final start = data.getUint16(starts + s * 2);
        for (var c = start; c <= end && c != 0xFFFF; c++) {
          points.add(c);
        }
      }
    } else if (format == 12) {
      final groups = data.getUint32(offset + 12);
      for (var g = 0; g < groups; g++) {
        final base = offset + 16 + g * 12;
        final start = data.getUint32(base);
        final end = data.getUint32(base + 4);
        for (var c = start; c <= end; c++) {
          points.add(c);
        }
      }
    }
  }
  return points;
}

void main() {
  // ά έ ή ί ό ύ ώ ΐ ΰ ϊ ϋ, the capitals with a tone and the basic alphabet.
  const toned = 'άέήίόύώΐΰϊϋΆΈΉΊΌΎΏΪΫ';
  const alphabet = 'αβγδεζηθικλμνξοπρσςτυφχψωΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ';

  for (final weight in ['Regular', 'Medium', 'SemiBold']) {
    test('NotoSans-$weight has the toned and the basic Greek letters', () {
      final bytes = File('assets/fonts/NotoSans-$weight.ttf').readAsBytesSync();
      final points = readCodePoints(bytes);
      final missing = [
        for (final rune in (toned + alphabet).runes)
          if (!points.contains(rune)) String.fromCharCode(rune),
      ];
      expect(missing, isEmpty, reason: 'missing in $weight: $missing');
    });
  }
}
