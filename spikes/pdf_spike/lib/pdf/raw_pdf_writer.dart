import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'layout.dart';

/// Approximate advance of a character in em (a proportional sans serif such as
/// Noto Sans). Only used to make the stretched hidden text look like the line
/// it covers (the highlight of a partial selection); the real extents come
/// from the layout.
double advanceEm(int cp) {
  if (cp == 0x20) return 0.26;
  if (cp >= 0x30 && cp <= 0x39) return 0.572;
  const narrow = '.,:;\'!|iljI’';
  if (cp < 0x80 && narrow.contains(String.fromCharCode(cp))) return 0.27;
  if (cp < 0x80 && 'mMwW'.contains(String.fromCharCode(cp))) return 0.86;
  if (cp < 0x80 && 'fjrt'.contains(String.fromCharCode(cp))) return 0.36;
  if (cp >= 0x41 && cp <= 0x5A) return 0.65;
  if (cp >= 0x61 && cp <= 0x7A) return 0.56;
  if (cp >= 0x391 && cp <= 0x3A9) return 0.70; // Greek capitals
  if (cp >= 0x3AC && cp <= 0x3CE) return 0.58; // Greek small
  return 0.58;
}

double naturalWidth(String s, double fontSize) {
  var em = 0.0;
  for (final r in s.runes) {
    em += advanceEm(r);
  }
  return em * fontSize;
}

/// Which hidden-text font the hand-written PDF uses.
enum GlyphlessFont {
  /// Type 3 font whose glyphs are empty procedures. No font file at all.
  /// (Measured: the PDF viewer of the emulator does NOT select this text.)
  type3,

  /// A TrueType font generated here with nothing but empty glyphs (about
  /// 1 KB), used as a CID font with Identity-H, so viewers see ordinary
  /// TrueType text.
  glyphlessTtf,
}

/// A PDF written by hand: the page picture (the JPEG bytes as they are, DCT)
/// and the hidden text in a "glyphless" Type 3 font: every glyph is an empty
/// procedure, so nothing is ever drawn and no font file is embedded, and a
/// `ToUnicode` map gives copy and search the right Unicode text.
///
/// Characters get codes 1..N in the order they appear (at most 250 distinct
/// characters per font; a further font is started when that is exceeded).
Uint8List buildRawPdf(
  List<PageSpec> pages,
  TextMode mode, {
  GlyphlessFont font = GlyphlessFont.type3,
}) {
  final w = _PdfWriter();
  final catalog = w.reserve();
  final pagesRoot = w.reserve();

  // Pass 1: runs and the character table.
  final allRuns = [for (final p in pages) layoutRuns(p, mode)];
  final table = _CharTable(
    perFont: font == GlyphlessFont.type3 ? _CharTable.type3PerFont : 60000,
  );
  for (final runs in allRuns) {
    for (final r in runs) {
      for (final c in r.text.runes) {
        table.add(c);
      }
    }
  }

  // Fonts.
  final fontRefs = <int>[];
  for (var f = 0; f < table.fontCount; f++) {
    fontRefs.add(
      font == GlyphlessFont.type3
          ? _writeFont(w, table, f)
          : _writeTtfFont(w, table.charsOf(f), f),
    );
  }

  final pageRefs = <int>[];
  for (var i = 0; i < pages.length; i++) {
    final spec = pages[i];
    final imageRef = w.add(
      '<< /Type /XObject /Subtype /Image /Width ${spec.page.width} '
      '/Height ${spec.page.height} /ColorSpace /DeviceRGB '
      '/BitsPerComponent 8 /Filter /DCTDecode /Length ${spec.jpeg.length} >>',
      stream: spec.jpeg,
    );
    final content = _content(
      spec,
      allRuns[i],
      table,
      twoByte: font == GlyphlessFont.glyphlessTtf,
    );
    final contentRef = w.add(
      '<< /Filter /FlateDecode /Length ${content.length} >>',
      stream: content,
    );
    final fonts = StringBuffer();
    for (var f = 0; f < fontRefs.length; f++) {
      fonts.write('/F${f + 1} ${fontRefs[f]} 0 R ');
    }
    final pw = _n(spec.pageWidth), ph = _n(spec.pageHeight);
    pageRefs.add(
      w.add(
        '<< /Type /Page /Parent $pagesRoot 0 R /MediaBox [0 0 $pw $ph] '
        '/Resources << /XObject << /Im0 $imageRef 0 R >> '
        '/Font << $fonts>> >> /Contents $contentRef 0 R >>',
      ),
    );
  }
  w.set(
    pagesRoot,
    '<< /Type /Pages /Kids [${pageRefs.map((r) => '$r 0 R').join(' ')}] '
    '/Count ${pageRefs.length} >>',
  );
  w.set(catalog, '<< /Type /Catalog /Pages $pagesRoot 0 R >>');
  return w.finish(catalog);
}

String _n(double v) {
  final s = v.toStringAsFixed(3);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

Uint8List _content(
  PageSpec spec,
  List<TextRun> runs,
  _CharTable table, {
  bool twoByte = false,
}) {
  final b = StringBuffer();
  b.writeln(
    'q ${_n(spec.pageWidth)} 0 0 ${_n(spec.pageHeight)} 0 0 cm /Im0 Do Q',
  );
  b.writeln('BT 3 Tr');
  for (final r in runs) {
    final natural = naturalWidth(r.text, r.fontSize);
    final tz = natural <= 0 ? 100.0 : r.width / natural * 100;
    final c = math.cos(r.angle), s = math.sin(r.angle);
    b.writeln('${_n(c)} ${_n(s)} ${_n(-s)} ${_n(c)} ${_n(r.x)} ${_n(r.y)} Tm');
    b.writeln('${_n(tz)} Tz');
    // One Tj per run of characters of the same font.
    var font = -1;
    final hex = StringBuffer();
    void flush() {
      if (hex.isNotEmpty) b.writeln('<$hex> Tj');
      hex.clear();
    }

    for (final cp in r.text.runes) {
      final (f, code) = table.lookup(cp);
      if (f != font) {
        flush();
        b.writeln('/F${f + 1} ${_n(r.fontSize)} Tf');
        font = f;
      }
      hex.write(code.toRadixString(16).padLeft(twoByte ? 4 : 2, '0'));
    }
    flush();
  }
  b.writeln('ET');
  return Uint8List.fromList(zlib.encode(utf8.encode(b.toString())));
}

int _writeFont(_PdfWriter w, _CharTable table, int font) {
  final chars = table.charsOf(font);
  // Empty glyph procedures: only the advance is given.
  final procNames = StringBuffer();
  final differences = StringBuffer('[1');
  final widths = StringBuffer();
  for (var i = 0; i < chars.length; i++) {
    final cp = chars[i];
    final width = (advanceEm(cp) * 1000).round();
    // A glyph box that is never painted (the text is rendered with mode 3);
    // an empty glyph gave the viewer nothing to select.
    final proc = '$width 0 0 -200 $width 800 d1 0 -200 $width 1000 re f';
    final ref = w.add(
      '<< /Length ${proc.length} >>',
      stream: Uint8List.fromList(utf8.encode(proc)),
    );
    procNames.write('/g${i + 1} $ref 0 R ');
    differences.write(' /g${i + 1}');
    widths.write('$width ');
  }
  differences.write(']');

  final cmap = StringBuffer()
    ..writeln('/CIDInit /ProcSet findresource begin')
    ..writeln('12 dict begin')
    ..writeln('begincmap')
    ..writeln(
      '/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def',
    )
    ..writeln('/CMapName /Adobe-Identity-UCS def')
    ..writeln('/CMapType 2 def')
    ..writeln('1 begincodespacerange')
    ..writeln('<00> <FF>')
    ..writeln('endcodespacerange');
  for (var start = 0; start < chars.length; start += 100) {
    final end = math.min(chars.length, start + 100);
    cmap.writeln('${end - start} beginbfchar');
    for (var i = start; i < end; i++) {
      final code = (i + 1).toRadixString(16).padLeft(2, '0');
      cmap.writeln('<$code> <${_utf16Hex(chars[i])}>');
    }
    cmap.writeln('endbfchar');
  }
  cmap
    ..writeln('endcmap')
    ..writeln('CMapName currentdict /CMap defineresource pop')
    ..writeln('end')
    ..writeln('end');
  final cmapBytes = Uint8List.fromList(utf8.encode(cmap.toString()));
  final toUnicode = w.add(
    '<< /Length ${cmapBytes.length} >>',
    stream: cmapBytes,
  );

  return w.add(
    '<< /Type /Font /Subtype /Type3 /Name /F${font + 1} '
    '/FontBBox [0 -250 1000 850] /FontMatrix [0.001 0 0 0.001 0 0] '
    '/CharProcs << $procNames>> '
    '/Encoding << /Type /Encoding /Differences $differences >> '
    '/FirstChar 1 /LastChar ${chars.length} /Widths [$widths] '
    '/ToUnicode $toUnicode 0 R /Resources << >> >>',
  );
}

String _utf16Hex(int cp) {
  String h(int v) => v.toRadixString(16).padLeft(4, '0');
  if (cp <= 0xFFFF) return h(cp);
  final v = cp - 0x10000;
  return h(0xD800 + (v >> 10)) + h(0xDC00 + (v & 0x3FF));
}

/// Maps characters to (font, code).
class _CharTable {
  _CharTable({required this.perFont});

  static const type3PerFont = 250;
  final int perFont;
  final _map = <int, (int, int)>{};
  final _fonts = <List<int>>[];

  int get fontCount => _fonts.length;

  void add(int cp) {
    if (_map.containsKey(cp)) return;
    if (_fonts.isEmpty || _fonts.last.length >= perFont) _fonts.add(<int>[]);
    _fonts.last.add(cp);
    _map[cp] = (_fonts.length - 1, _fonts.last.length);
  }

  (int, int) lookup(int cp) => _map[cp]!;

  List<int> charsOf(int font) => _fonts[font];
}

class _PdfWriter {
  final _bodies = <int, Uint8List>{};
  var _next = 1;

  int reserve() => _next++;

  int add(String dict, {Uint8List? stream}) {
    final n = _next++;
    set(n, dict, stream: stream);
    return n;
  }

  void set(int n, String dict, {Uint8List? stream}) {
    final out = BytesBuilder();
    out.add(latin1.encode('$n 0 obj\n$dict\n'));
    if (stream != null) {
      out.add(latin1.encode('stream\n'));
      out.add(stream);
      out.add(latin1.encode('\nendstream\n'));
    }
    out.add(latin1.encode('endobj\n'));
    _bodies[n] = out.toBytes();
  }

  Uint8List finish(int root) {
    final out = BytesBuilder();
    out.add(latin1.encode('%PDF-1.5\n%âãÏÓ\n'));
    final offsets = <int, int>{};
    var pos = out.length;
    for (var n = 1; n < _next; n++) {
      offsets[n] = pos;
      final body = _bodies[n]!;
      out.add(body);
      pos += body.length;
    }
    final xref = pos;
    final x = StringBuffer('xref\n0 $_next\n0000000000 65535 f \n');
    for (var n = 1; n < _next; n++) {
      x.write('${offsets[n].toString().padLeft(10, '0')} 00000 n \n');
    }
    x.write(
      'trailer\n<< /Size $_next /Root $root 0 R >>\nstartxref\n$xref\n%%EOF\n',
    );
    out.add(latin1.encode(x.toString()));
    return out.toBytes();
  }
}

/// Type 0 font over the generated glyphless TrueType: CID = code 1..N, glyph
/// id = CID (`CIDToGIDMap /Identity`), every glyph empty, widths from the
/// `W` array, Unicode from `ToUnicode`.
int _writeTtfFont(_PdfWriter w, List<int> chars, int font) {
  final glyphWidths = [
    1000,
    for (final cp in chars) (advanceEm(cp) * 1000).round(),
  ];
  final ttf = glyphlessTtf(glyphWidths);
  final packed = Uint8List.fromList(zlib.encode(ttf));
  final file = w.add(
    '<< /Filter /FlateDecode /Length ${packed.length} /Length1 ${ttf.length} >>',
    stream: packed,
  );
  const name = '/AAAAAA+Glyphless';
  final descriptor = w.add(
    '<< /Type /FontDescriptor /FontName $name /Flags 4 '
    '/FontBBox [0 -250 1000 850] /ItalicAngle 0 /Ascent 800 /Descent -200 '
    '/CapHeight 700 /StemV 80 /FontFile2 $file 0 R >>',
  );
  final widths = StringBuffer('[');
  for (final cp in chars) {
    widths.write('${(advanceEm(cp) * 1000).round()} ');
  }
  widths.write(']');
  final cid = w.add(
    '<< /Type /Font /Subtype /CIDFontType2 /BaseFont $name '
    '/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> '
    '/FontDescriptor $descriptor 0 R /DW 600 /W [1 $widths] '
    '/CIDToGIDMap /Identity >>',
  );

  final cmap = StringBuffer()
    ..writeln('/CIDInit /ProcSet findresource begin')
    ..writeln('12 dict begin')
    ..writeln('begincmap')
    ..writeln(
      '/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def',
    )
    ..writeln('/CMapName /Adobe-Identity-UCS def')
    ..writeln('/CMapType 2 def')
    ..writeln('1 begincodespacerange')
    ..writeln('<0000> <FFFF>')
    ..writeln('endcodespacerange');
  for (var start = 0; start < chars.length; start += 100) {
    final end = math.min(chars.length, start + 100);
    cmap.writeln('${end - start} beginbfchar');
    for (var i = start; i < end; i++) {
      final code = (i + 1).toRadixString(16).padLeft(4, '0');
      cmap.writeln('<$code> <${_utf16Hex(chars[i])}>');
    }
    cmap.writeln('endbfchar');
  }
  cmap
    ..writeln('endcmap')
    ..writeln('CMapName currentdict /CMap defineresource pop')
    ..writeln('end')
    ..writeln('end');
  final cmapBytes = Uint8List.fromList(utf8.encode(cmap.toString()));
  final toUnicode = w.add(
    '<< /Length ${cmapBytes.length} >>',
    stream: cmapBytes,
  );
  return w.add(
    '<< /Type /Font /Subtype /Type0 /BaseFont $name /Encoding /Identity-H '
    '/DescendantFonts [$cid 0 R] /ToUnicode $toUnicode 0 R >>',
  );
}

/// A TrueType font whose glyphs are only an empty-looking box: every glyph is
/// a rectangle as wide as its advance and 1 em high. The text is always drawn
/// with render mode 3 (invisible), so the box is never painted, but the viewer
/// needs a non-empty glyph box: with truly empty glyphs the emulator's viewer
/// did not select the text at all. Glyphs of equal width share one outline.
/// [widths] are the advances in 1000 units per em, glyph 0 first.
Uint8List glyphlessTtf(List<int> widths) {
  final numGlyphs = widths.length;
  Uint8List be(List<(int, int)> fields) {
    final b = BytesBuilder();
    for (final (size, value) in fields) {
      for (var i = size - 1; i >= 0; i--) {
        b.addByte((value >> (8 * i)) & 0xFF);
      }
    }
    return b.toBytes();
  }

  // One rectangle outline per distinct width.
  const yMin = -200, yMax = 800;
  final distinct = widths.toSet().toList()..sort();
  final glyf = BytesBuilder();
  final offsetOf = <int, int>{};
  for (final wd in distinct) {
    offsetOf[wd] = glyf.length;
    glyf.add(
      be([
        (2, 1), (2, 0), (2, yMin & 0xFFFF), (2, wd), (2, yMax),
        (2, 3), (2, 0), // endPtsOfContours[0] = 3, instructionLength = 0
        (1, 1), (1, 1), (1, 1), (1, 1), // flags: on curve, 16-bit deltas
        (2, 0), (2, wd), (2, 0), (2, (-wd) & 0xFFFF), // x deltas
        (2, yMin & 0xFFFF), (2, 0), (2, yMax - yMin), (2, 0), // y deltas
      ]),
    );
  }
  final glyfBytes = glyf.toBytes();
  final loca = BytesBuilder();
  for (final wd in widths) {
    loca.add(be([(2, offsetOf[wd]! ~/ 2)]));
  }
  loca.add(be([(2, glyfBytes.length ~/ 2)]));
  final maxW = distinct.last;

  final head = be([
    (4, 0x00010000), (4, 0x00010000), (4, 0), (4, 0x5F0F3CF5), (2, 3),
    (2, 1000), (4, 0), (4, 0), (4, 0), (4, 0), // created, modified (int64 x2)
    (2, 0), (2, yMin & 0xFFFF), (2, maxW), (2, yMax), // bbox
    (2, 0), (2, 8), (2, 2), (2, 0), (2, 0),
  ]);
  final hhea = be([
    (4, 0x00010000),
    (2, 800),
    (2, 0x10000 - 200),
    (2, 0),
    (2, maxW),
    (2, 0),
    (2, 0),
    (2, maxW),
    (2, 1),
    (2, 0),
    (2, 0),
    (2, 0),
    (2, 0),
    (2, 0),
    (2, 0),
    (2, 0),
    (2, numGlyphs),
  ]);
  final maxp = be([
    (4, 0x00010000),
    (2, numGlyphs),
    (2, 4),
    (2, 1),
    (2, 0),
    (2, 0),
    (2, 1),
    (2, 0),
    (2, 0),
    (2, 0),
    (2, 0),
    (2, 0),
    (2, 0),
    (2, 0),
    (2, 0),
  ]);
  final hmtx = BytesBuilder();
  for (final wd in widths) {
    hmtx.add(be([(2, wd), (2, 0)]));
  }
  final cmap = be([
    (2, 0),
    (2, 1),
    (2, 3),
    (2, 1),
    (4, 12),
    (2, 4),
    (2, 24),
    (2, 0),
    (2, 2),
    (2, 2),
    (2, 0),
    (2, 0),
    (2, 0xFFFF),
    (2, 0),
    (2, 0xFFFF),
    (2, 1),
    (2, 0),
  ]);
  final name = be([(2, 0), (2, 0), (2, 6)]);
  final post = be([
    (4, 0x00030000),
    (4, 0),
    (2, 0),
    (2, 0),
    (4, 0),
    (4, 0),
    (4, 0),
    (4, 0),
    (4, 0),
  ]);

  final tables = <String, Uint8List>{
    'cmap': cmap,
    'glyf': glyfBytes,
    'head': head,
    'hhea': hhea,
    'hmtx': hmtx.toBytes(),
    'loca': loca.toBytes(),
    'maxp': maxp,
    'name': name,
    'post': post,
  };
  final n = tables.length;
  var entrySelector = 0;
  while ((1 << (entrySelector + 1)) <= n) {
    entrySelector++;
  }
  final searchRange = (1 << entrySelector) * 16;
  final out = BytesBuilder();
  out.add(
    be([
      (4, 0x00010000),
      (2, n),
      (2, searchRange),
      (2, entrySelector),
      (2, n * 16 - searchRange),
    ]),
  );
  var offset = 12 + n * 16;
  final bodies = BytesBuilder();
  for (final e in tables.entries) {
    final data = e.value;
    final padded = (data.length + 3) & ~3;
    var sum = 0;
    for (var i = 0; i < padded; i += 4) {
      var v = 0;
      for (var k = 0; k < 4; k++) {
        v = (v << 8) | (i + k < data.length ? data[i + k] : 0);
      }
      sum = (sum + v) & 0xFFFFFFFF;
    }
    out.add(latin1.encode(e.key));
    out.add(be([(4, sum), (4, offset), (4, data.length)]));
    bodies.add(data);
    bodies.add(Uint8List(padded - data.length));
    offset += padded;
  }
  out.add(bodies.toBytes());
  return out.toBytes();
}
