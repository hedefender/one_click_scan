import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/presentation/licenses/ocr_licenses.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';

/// The font of the text layer is bundled in the app (SIL OFL 1.1). These tests
/// pin the file and check that it can draw what the OCR packs can read.
void main() {
  const fontPath = 'assets/fonts/NotoSans-Regular.ttf';
  const fontSha256 =
      '478c558ea716033cd60c03438f628dfa75694dcf6b5f6d505a2f05fd2b4f3823';

  test('the font file is the pinned Noto Sans Regular', () {
    final bytes = File(fontPath).readAsBytesSync();

    expect(bytes.length, 621572);
    expect(sha256.convert(bytes).toString(), fontSha256);
  });

  test('its licence text is bundled and is the SIL Open Font License', () {
    final text = File('assets/licenses/notosans_OFL.txt').readAsStringSync();

    expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'));
    expect(text, contains('Noto Project Authors'));
  });

  test('the licence screen lists Noto Sans with that text', () async {
    LicenseRegistry.reset();
    registerOcrLicenses(
      loadAsset: (path) async => File(path).readAsStringSync(),
    );

    final entries = await LicenseRegistry.licenses.toList();
    final noto = entries.firstWhere((e) => e.packages.contains('Noto Sans'));

    expect(
      noto.paragraphs.map((p) => p.text).join(' '),
      contains('SIL OPEN FONT'),
    );
    expect(
      entries.expand((e) => e.packages),
      containsAll(['PaddleOCR PP-OCRv5 models', 'ONNX Runtime', 'Noto Sans']),
    );
  });

  group('the font covers the recognition packs', () {
    late PdfTtfFont font;

    setUpAll(() {
      final bytes = File(fontPath).readAsBytesSync();
      font = PdfTtfFont(PdfDocument(), ByteData.sublistView(bytes));
    });

    bool covers(int rune) => font.isRuneSupported(rune);

    test('Greek: capitals, small letters, final sigma, every accent', () {
      const greek =
          'ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩαβγδεζηθικλμνξοπρσςτυφχψω'
          'ΆΈΉΊΌΎΏάέήίόύώΪΫϊϋΐΰ';
      for (final rune in greek.runes) {
        expect(covers(rune), isTrue, reason: String.fromCharCode(rune));
      }
    });

    test('Latin: ASCII letters, digits, punctuation, the euro sign', () {
      const latin =
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
          ' .,;:!?-_/\\()[]{}"\'@#%&*+=<>€£\$§°';
      for (final rune in latin.runes) {
        expect(covers(rune), isTrue, reason: String.fromCharCode(rune));
      }
    });

    test('Latin with accents of the Latin pack languages', () {
      const accents =
          'àáâãäåæçèéêëìíîïñòóôõöøùúûüýÿœßÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÑÒÓÔÕÖØÙÚÛÜÝŒ'
          'ąćęłńśźżčďěňřšťůžőű';
      for (final rune in accents.runes) {
        expect(covers(rune), isTrue, reason: String.fromCharCode(rune));
      }
    });

    test('every character of both dictionaries: the share the font has', () {
      // The dictionaries are model assets (not in git): skip when absent.
      for (final pack in ['greek', 'latin']) {
        final file = File('assets/ocr/models/dict_$pack.txt');
        if (!file.existsSync()) continue;
        final chars = file
            .readAsStringSync()
            .split('\n')
            .map((l) => l.replaceAll('\r', ''))
            .where((l) => l.isNotEmpty)
            .toList();
        final missing = [
          for (final c in chars)
            if (!c.runes.every(covers)) c,
        ];
        // Printed for the notes of the phase (numbers only).
        // ignore: avoid_print
        print(
          'font coverage $pack: ${chars.length - missing.length} of '
          '${chars.length} dictionary characters',
        );
        // A character the font lacks is left out of the hidden text, which
        // is a convenience; but the common ones must be there.
        expect(missing.length / chars.length, lessThan(0.5));
      }
    });
  });
}
