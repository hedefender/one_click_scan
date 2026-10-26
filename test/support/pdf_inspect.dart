import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A small JPEG without any metadata, made of a flat colour, written to
/// [path].
Uint8List writeTestJpeg(String path, int width, int height, {int shade = 200}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(shade, shade, shade));
  final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 90));
  File(path).writeAsBytesSync(bytes);
  return bytes;
}

/// A look inside the bytes of a PDF written by the `pdf` package, without a
/// PDF library: the raw text, plus every stream that inflates.
class PdfInspector {
  PdfInspector(this.bytes) {
    final raw = latin1.decode(bytes);
    _raw = raw;
    final inflated = StringBuffer();
    var from = 0;
    while (true) {
      final start = raw.indexOf('stream', from);
      if (start < 0) break;
      if (start >= 3 && raw.substring(start - 3, start) == 'end') {
        from = start + 6;
        continue;
      }
      var begin = start + 6;
      if (raw.codeUnitAt(begin) == 13) begin++;
      if (raw.codeUnitAt(begin) == 10) begin++;
      final end = raw.indexOf('endstream', begin);
      if (end < 0) break;
      try {
        final data = ZLibDecoder().convert(bytes.sublist(begin, end));
        inflated.writeln(latin1.decode(data, allowInvalid: true));
      } catch (_) {
        // Not deflated (a JPEG, a font table): ignore.
      }
      from = end + 9;
    }
    _inflated = inflated.toString();
  }

  final Uint8List bytes;
  late final String _raw;
  late final String _inflated;

  /// The file as text (binary streams are noise) followed by every inflated
  /// stream: what a search for a marker needs.
  String get everything => '$_raw\n$_inflated';

  String get content => _inflated;

  int get pageCount =>
      RegExp(r'/Type\s*/Page(?![a-zA-Z])').allMatches(_raw).length;

  /// The `/MediaBox [0 0 w h]` of every page, in order.
  List<(double, double)> get mediaBoxes => [
    for (final m in RegExp(
      r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]',
    ).allMatches(_raw))
      (double.parse(m.group(1)!), double.parse(m.group(2)!)),
  ];

  int get imageCount => RegExp(r'/Subtype\s*/Image').allMatches(_raw).length;

  bool get usesJpegFilter => _raw.contains('/DCTDecode');

  /// Number of text pieces drawn invisibly (`3 Tr`).
  int get invisibleTextCount =>
      RegExp(r'\b3 Tr\b').allMatches(_inflated).length;

  /// Number of text pieces drawn with another render mode (visible text).
  int get visibleTextCount =>
      RegExp(r'\b[0124567] Tr\b').allMatches(_inflated).length;

  bool get hasToUnicode => _raw.contains('/ToUnicode');

  /// Every Unicode character of the `ToUnicode` maps (`<code> <unicode>`).
  Set<String> get toUnicodeCharacters {
    final out = <String>{};
    for (final m in RegExp(
      r'<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]{4,8})>',
    ).allMatches(_inflated)) {
      final hex = m.group(2)!;
      final units = <int>[
        for (var i = 0; i < hex.length; i += 4)
          int.parse(hex.substring(i, i + 4), radix: 16),
      ];
      out.add(String.fromCharCodes(units));
    }
    return out;
  }

  /// True when [needle] (the bytes of a file) appears unchanged inside the
  /// PDF, as it does for a JPEG that was not recompressed.
  bool containsBytes(Uint8List needle) {
    outer:
    for (var i = 0; i + needle.length <= bytes.length; i++) {
      if (bytes[i] != needle[0]) continue;
      for (var j = 1; j < needle.length; j++) {
        if (bytes[i + j] != needle[j]) continue outer;
      }
      return true;
    }
    return false;
  }
}
