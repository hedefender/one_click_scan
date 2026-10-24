import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf_spike/ocr/spike_ocr.dart';
import 'package:pdf_spike/ocr/text_box.dart';
import 'package:pdf_spike/pdf/layout.dart';
import 'package:pdf_spike/pdf/raw_pdf_writer.dart';

/// "RF12 345" on a 1000 x 200 picture: the line box is 400 x 40 centred at
/// (500, 40); the characters are 50 px wide each.
SpikePage fakePage() {
  const text = 'RF12 345';
  final chars = [
    for (var i = 0; i < text.length; i++)
      CharSpan(text[i], i / text.length, (i + 1) / text.length),
  ];
  return SpikePage(1000, 200, [
    SpikeLine(text, 0.99, TextBox(500, 40, 400, 40, 0), chars, 0),
  ], 1);
}

Uint8List jpeg() => img.encodeJpg(img.Image(width: 1000, height: 200));

void main() {
  glyphlessTtfTests();
  test('mode A is one run, B one per word, C one per character of a code', () {
    final spec = PageSpec(jpeg: jpeg(), page: fakePage());

    expect(layoutRuns(spec, TextMode.line).map((r) => r.text), ['RF12 345']);
    expect(layoutRuns(spec, TextMode.word).map((r) => r.text), ['RF12', '345']);
    expect(
      layoutRuns(spec, TextMode.code).map((r) => r.text),
      ['R', 'F', '1', '2', '3', '4', '5'].where((c) => true),
    );
  });

  test('a word run starts and ends where its characters do', () {
    final spec = PageSpec(jpeg: jpeg(), page: fakePage());
    final k = spec.scale; // 0.595 points per pixel
    final second = layoutRuns(spec, TextMode.word)[1];

    // "345" covers fractions 5/8..1 of a 400 px box starting at x = 300.
    expect(second.x, closeTo((300 + 0.625 * 400) * k, 1e-6));
    expect(second.width, closeTo(0.375 * 400 * k, 1e-6));
  });

  test('page y is flipped: the line is in the upper half of the picture', () {
    final spec = PageSpec(jpeg: jpeg(), page: fakePage());
    final run = layoutRuns(spec, TextMode.line).single;

    expect(run.y, greaterThan(spec.pageHeight / 2 - 5));
    expect(run.angle, 0);
  });

  test(
    'the raw PDF is well formed: header, xref offsets, ToUnicode, no EXIF',
    () {
      final spec = PageSpec(jpeg: jpeg(), page: fakePage());
      final bytes = buildRawPdf([spec], TextMode.word);
      final text = latin1.decode(bytes);

      expect(text.startsWith('%PDF-1.5'), isTrue);
      expect(text.trimRight().endsWith('%%EOF'), isTrue);
      final xref = int.parse(RegExp(r'startxref\n(\d+)').firstMatch(text)![1]!);
      expect(text.substring(xref).startsWith('xref'), isTrue);
      for (final m in RegExp(r'(\d{10}) 00000 n').allMatches(text)) {
        final off = int.parse(m[1]!);
        expect(text.substring(off), matches(RegExp(r'^\d+ 0 obj')));
      }
      expect(text, contains('/ToUnicode'));
      expect(text, contains('/Subtype /Type3'));
      expect(text, isNot(contains('Exif')));
      expect(text, isNot(contains('/Info')));
    },
  );

  test('more than 250 distinct characters start a second font', () {
    final text = String.fromCharCodes([
      for (var c = 0x400; c < 0x400 + 300; c++) c,
    ]);
    final chars = [
      for (var i = 0; i < text.length; i++)
        CharSpan(text[i], i / 300, (i + 1) / 300),
    ];
    final page = SpikePage(1000, 200, [
      SpikeLine(text, 0.9, TextBox(500, 100, 900, 40, 0), chars, 0),
    ], 1);

    final pdf = latin1.decode(
      buildRawPdf([PageSpec(jpeg: jpeg(), page: page)], TextMode.line),
    );

    expect(RegExp(r'/Subtype /Type3').allMatches(pdf).length, 2);
  });
}

void glyphlessTtfTests() {
  test('the generated glyphless TrueType has a valid table directory', () {
    final ttf = glyphlessTtf([
      1000,
      for (var i = 1; i < 200; i++) 500 + i % 7 * 50,
    ]);
    final data = ByteData.sublistView(ttf);

    expect(data.getUint32(0), 0x00010000);
    final n = data.getUint16(4);
    expect(n, 9);
    final tags = <String, (int, int)>{};
    for (var i = 0; i < n; i++) {
      final at = 12 + i * 16;
      final tag = String.fromCharCodes(ttf.sublist(at, at + 4));
      tags[tag] = (data.getUint32(at + 8), data.getUint32(at + 12));
    }
    for (final t in ['head', 'hhea', 'maxp', 'hmtx', 'loca', 'glyf', 'cmap']) {
      expect(tags, contains(t));
      expect(tags[t]!.$1 + tags[t]!.$2, lessThanOrEqualTo(ttf.length));
    }
    expect(data.getUint32(tags['head']!.$1 + 12), 0x5F0F3CF5);
    expect(data.getUint16(tags['maxp']!.$1 + 4), 200);
    expect(tags['loca']!.$2, 201 * 2);
    expect(tags['hmtx']!.$2, 200 * 4);
    expect(ttf.length, lessThan(3000));
  });

  test('the PDF with the glyphless TrueType has a Type0 font and no Type3', () {
    final spec = PageSpec(jpeg: jpeg(), page: fakePage());
    final text = latin1.decode(
      buildRawPdf([spec], TextMode.word, font: GlyphlessFont.glyphlessTtf),
    );

    expect(text, contains('/Subtype /Type0'));
    expect(text, contains('/CIDToGIDMap /Identity'));
    expect(text, contains('/FontFile2'));
    expect(text, isNot(contains('/Type3')));
  });
}
