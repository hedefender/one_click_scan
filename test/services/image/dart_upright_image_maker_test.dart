import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:one_click_scan/domain/ports/upright_image_maker.dart';
import 'package:one_click_scan/services/image/dart_upright_image_maker.dart';
import 'package:one_click_scan/services/image/image_header_parser.dart';

import '../../../integration_test/support/synthetic_pages.dart'
    show storedFor, writeJpeg;

/// 60 x 40 with four coloured quadrants, so any rotation or flip shows.
img.Image quadrants() {
  final image = img.Image(width: 60, height: 40);
  final colours = {
    (0, 0): img.ColorRgb8(255, 0, 0), // top-left red
    (1, 0): img.ColorRgb8(0, 200, 0), // top-right green
    (0, 1): img.ColorRgb8(0, 0, 255), // bottom-left blue
    (1, 1): img.ColorRgb8(255, 255, 0), // bottom-right yellow
  };
  for (var y = 0; y < 40; y++) {
    for (var x = 0; x < 60; x++) {
      image.setPixel(x, y, colours[(x < 30 ? 0 : 1, y < 20 ? 0 : 1)]!);
    }
  }
  return image;
}

bool near(img.Pixel p, int r, int g, int b) =>
    (p.r - r).abs() < 70 && (p.g - g).abs() < 70 && (p.b - b).abs() < 70;

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('upright_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  (int, int) make(File source, {int maxSide = 2560}) =>
      makeUprightSync(source.path, '${dir.path}/out.jpg', maxSide, 92);

  img.Image result() =>
      img.decodeJpg(File('${dir.path}/out.jpg').readAsBytesSync())!;

  group('EXIF orientation 1..8 gives the upright picture back', () {
    for (final orientation in [1, 2, 3, 4, 5, 6, 7, 8]) {
      test('orientation $orientation', () {
        final stored = storedFor(quadrants(), orientation);
        final file = writeJpeg(
          '${dir.path}/in.jpg',
          stored,
          exifOrientation: orientation,
          quality: 95,
        );

        final (w, h) = make(file);

        // Always the upright 60 x 40 landscape, never the stored shape.
        expect((w, h), (60, 40));
        final out = result();
        expect(near(out.getPixel(10, 5), 255, 0, 0), isTrue, reason: 'TL red');
        expect(
          near(out.getPixel(50, 5), 0, 200, 0),
          isTrue,
          reason: 'TR green',
        );
        expect(
          near(out.getPixel(10, 35), 0, 0, 255),
          isTrue,
          reason: 'BL blue',
        );
        expect(
          near(out.getPixel(50, 35), 255, 255, 0),
          isTrue,
          reason: 'BR yellow',
        );
      });
    }
  });

  group('invalid orientation values mean no rotation', () {
    for (final value in [0, 9, 200]) {
      test('tag $value', () {
        final file = writeJpeg(
          '${dir.path}/in.jpg',
          quadrants(),
          exifOrientation: value,
          quality: 95,
        );

        final (w, h) = make(file);

        expect((w, h), (60, 40));
        expect(near(result().getPixel(10, 5), 255, 0, 0), isTrue);
      });
    }
  });

  group('the size is that of the decoded pixels', () {
    test('false EXIF size tags do not change it', () {
      final image = img.Image(width: 972, height: 1260);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      image.exif.exifIfd[0xA002] = img.IfdValueShort(1840);
      image.exif.exifIfd[0xA003] = img.IfdValueShort(4080);
      final file = File('${dir.path}/xiaomi.jpg')
        ..writeAsBytesSync(img.encodeJpg(image));

      final (w, h) = make(file);

      expect((w, h), (972, 1260));
    });

    test('a rotated photo reports the rotated size', () {
      final stored = storedFor(quadrants(), 6); // 40 x 60 stored
      expect((stored.width, stored.height), (40, 60));
      final file = writeJpeg('${dir.path}/in.jpg', stored, exifOrientation: 6);

      expect(make(file), (60, 40));
    });
  });

  group('scaling', () {
    test('the long side is cut to maxSide, the aspect ratio is kept', () {
      final big = img.Image(width: 3000, height: 2000);
      img.fill(big, color: img.ColorRgb8(255, 255, 255));
      final file = writeJpeg('${dir.path}/big.jpg', big, exifOrientation: 1);

      final (w, h) = make(file, maxSide: 1500);

      expect((w, h), (1500, 1000));
    });

    test('a portrait photo is scaled by its height', () {
      final big = img.Image(width: 2000, height: 3000);
      img.fill(big, color: img.ColorRgb8(255, 255, 255));
      final file = writeJpeg('${dir.path}/big.jpg', big);

      final (w, h) = make(file, maxSide: 1500);

      expect((w, h), (1000, 1500));
    });

    test('a small photo is not enlarged', () {
      final file = writeJpeg('${dir.path}/small.jpg', quadrants());

      expect(make(file), (60, 40));
    });
  });

  group('failures', () {
    test('a file that is not an image is unreadable', () {
      final file = File('${dir.path}/notes.jpg')..writeAsStringSync('text');

      expect(
        () => make(file),
        throwsA(
          isA<UprightImageException>().having(
            (e) => e.code,
            'code',
            'unreadable',
          ),
        ),
      );
    });

    test(
      'the async maker runs in an isolate and reports the same size',
      () async {
        final file = writeJpeg(
          '${dir.path}/in.jpg',
          storedFor(quadrants(), 6),
          exifOrientation: 6,
        );

        final pixels = await const DartUprightImageMaker().make(
          source: file.path,
          target: '${dir.path}/async.jpg',
          maxSide: 2560,
          jpegQuality: 95,
        );

        expect((pixels.width, pixels.height), (60, 40));
        expect(File('${dir.path}/async.jpg').existsSync(), isTrue);
      },
    );

    test('a missing file is reported as a failure, not an exception', () async {
      await expectLater(
        const DartUprightImageMaker().make(
          source: '${dir.path}/missing.jpg',
          target: '${dir.path}/o.jpg',
          maxSide: 2560,
          jpegQuality: 95,
        ),
        throwsA(isA<UprightImageException>()),
      );
    });
  });

  test('the header reader and the maker agree on the orientation', () {
    final file = writeJpeg(
      '${dir.path}/in.jpg',
      storedFor(quadrants(), 8),
      exifOrientation: 8,
    );

    final header = parseImageHeader(BytesSource(file.readAsBytesSync()))!;

    expect(header.orientation, 8);
    expect((header.width, header.height), (40, 60));
  });
}
