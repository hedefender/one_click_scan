import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:one_click_scan/domain/pdf/pdf_text_layout.dart';
import 'package:one_click_scan/services/image/dart_upright_image_maker.dart';
import 'package:one_click_scan/services/pdf/pdf_writer.dart';

import '../../../integration_test/support/synthetic_pages.dart' show storedFor;
import '../../support/pdf_inspect.dart';
import 'dart_upright_image_maker_test.dart' show near, quadrants;

/// The working copy is the picture of the PDF when the crop keeps the whole
/// frame (`StraightenPage`), so a camera's metadata in it would travel in the
/// e-mail (A1-005, ADR-017). Only the Dart path (photos up to 8 MP) kept it;
/// the native path never wrote EXIF. The photo here is invented: the model
/// name, the time and the position are made up.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('exif_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  const make = 'SyntheticMake';
  const model = 'SyntheticModel-X1';
  const time = '2026:01:02 03:04:05';

  File photoWithExif(int orientation) {
    final stored = storedFor(quadrants(), orientation);
    stored.exif.imageIfd['Make'] = img.IfdValueAscii(make);
    stored.exif.imageIfd['Model'] = img.IfdValueAscii(model);
    stored.exif.imageIfd['DateTime'] = img.IfdValueAscii(time);
    stored.exif.imageIfd.orientation = orientation;
    stored.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
    stored.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(37, 1);
    return File('${dir.path}/in_$orientation.jpg')
      ..writeAsBytesSync(img.encodeJpg(stored, quality: 95));
  }

  bool hasApp1(Uint8List jpeg) {
    var pos = 2;
    while (pos + 4 <= jpeg.length && jpeg[pos] == 0xFF) {
      final marker = jpeg[pos + 1];
      if (marker == 0xDA) break;
      if (marker == 0xE1) return true;
      pos += 2 + ((jpeg[pos + 2] << 8) | jpeg[pos + 3]);
    }
    return false;
  }

  test(
    'the invented photo really carries the metadata (the test can fail)',
    () {
      final bytes = photoWithExif(6).readAsBytesSync();
      final text = latin1.decode(bytes);
      expect(hasApp1(bytes), isTrue);
      expect(text, contains(model));
      expect(text, contains(time));
    },
  );

  for (final orientation in [1, 2, 3, 4, 5, 6, 7, 8]) {
    test('orientation $orientation: no EXIF in the working copy, and the '
        'picture is still upright', () {
      final source = photoWithExif(orientation);
      final target = '${dir.path}/work_$orientation.jpg';

      final (w, h) = makeUprightSync(source.path, target, 2560, 95);

      final bytes = File(target).readAsBytesSync();
      final text = latin1.decode(bytes);
      expect(hasApp1(bytes), isFalse, reason: 'APP1 marker');
      for (final needle in [make, model, '2026:01', 'Exif', 'GPS']) {
        expect(text, isNot(contains(needle)), reason: needle);
      }
      // The same upright picture as without the clean-up.
      expect((w, h), (60, 40));
      final out = img.decodeJpg(bytes)!;
      expect(out.exif.imageIfd.hasOrientation, isFalse);
      expect(near(out.getPixel(10, 5), 255, 0, 0), isTrue, reason: 'TL red');
      expect(near(out.getPixel(50, 5), 0, 200, 0), isTrue, reason: 'TR green');
      expect(near(out.getPixel(10, 35), 0, 0, 255), isTrue, reason: 'BL blue');
      expect(near(out.getPixel(50, 35), 255, 255, 0), isTrue, reason: 'BR');
    });
  }

  test('a photo that is scaled down is clean too', () {
    final source = photoWithExif(6);
    final target = '${dir.path}/small.jpg';

    makeUprightSync(source.path, target, 30, 95);

    final bytes = File(target).readAsBytesSync();
    expect(hasApp1(bytes), isFalse);
    expect(latin1.decode(bytes), isNot(contains(model)));
  });

  test('the PDF made of that working copy (the whole frame kept) has no '
      'metadata of the photo', () async {
    final source = photoWithExif(6);
    final work = '${dir.path}/work.jpg';
    final (w, h) = makeUprightSync(source.path, work, 2560, 95);
    final out = '${dir.path}/out.pdf';

    await writePdf(
      PdfJob(
        pages: [
          PdfPageJob(
            imagePath: work,
            widthPx: w,
            heightPx: h,
            runs: const <PdfTextRun>[],
          ),
        ],
        fontBytes: File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync(),
        outputPath: out,
      ),
    );

    final pdf = PdfInspector(File(out).readAsBytesSync());
    expect(pdf.containsBytes(File(work).readAsBytesSync()), isTrue);
    for (final needle in [make, model, '2026:01', 'Exif', 'GPS']) {
      expect(pdf.everything, isNot(contains(needle)), reason: needle);
    }
  });
}
