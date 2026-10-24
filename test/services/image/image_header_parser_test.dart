import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:one_click_scan/services/image/image_header_parser.dart';

/// A JPEG with the given EXIF orientation tag (any value, including 0).
Uint8List jpegWith(int width, int height, {int? orientation}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(200, 200, 200));
  if (orientation != null) image.exif.imageIfd.orientation = orientation;
  return img.encodeJpg(image);
}

/// Builds `Exif\0\0` + a TIFF block with one tag 0x0112 = [value].
Uint8List exifPayload(int value, {required bool little}) {
  final b = BytesBuilder();
  b.add([0x45, 0x78, 0x69, 0x66, 0, 0]);
  void u16(int v) => b.add(little ? [v & 0xFF, v >> 8] : [v >> 8, v & 0xFF]);
  void u32(int v) => b.add(
    little
        ? [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, v >> 24]
        : [v >> 24, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF],
  );
  b.add(little ? [0x49, 0x49] : [0x4D, 0x4D]);
  u16(42);
  u32(8);
  u16(1); // one entry
  u16(0x0112);
  u16(3); // SHORT
  u32(1);
  u16(value);
  u16(0);
  u32(0);
  return b.toBytes();
}

void main() {
  group('size from the header, nothing decoded', () {
    test('JPEG', () {
      final header = parseImageHeader(BytesSource(jpegWith(640, 480)))!;

      expect(header.width, 640);
      expect(header.height, 480);
      expect(header.megapixels, closeTo(0.307, 0.001));
    });

    test('PNG', () {
      final image = img.Image(width: 120, height: 90);
      final header = parseImageHeader(BytesSource(img.encodePng(image)))!;

      expect(header.width, 120);
      expect(header.height, 90);
      expect(header.orientation, 1);
    });

    test('a 200 MP header is read as 200 MP without any pixels', () {
      final bytes = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x11, 0x08, //
        16320 >> 8, 16320 & 0xFF, 12240 >> 8, 12240 & 0xFF,
        0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
      ]);

      final header = parseImageHeader(BytesSource(bytes))!;

      expect(header.width, 12240);
      expect(header.height, 16320);
      expect(header.megapixels, closeTo(199.8, 0.1));
    });

    test('not an image, empty and truncated data give null', () {
      expect(parseImageHeader(BytesSource(Uint8List(0))), isNull);
      expect(
        parseImageHeader(BytesSource(Uint8List.fromList([1, 2, 3]))),
        isNull,
      );
      expect(
        parseImageHeader(BytesSource(Uint8List.fromList([0xFF, 0xD8, 0xFF]))),
        isNull,
      );
      final cut = jpegWith(64, 64).sublist(0, 12);
      expect(parseImageHeader(BytesSource(cut)), isNull);
    });
  });

  group('EXIF orientation', () {
    for (final value in [1, 2, 3, 4, 5, 6, 7, 8]) {
      test('tag $value is read back as $value', () {
        final header = parseImageHeader(
          BytesSource(jpegWith(40, 20, orientation: value)),
        )!;

        expect(header.orientation, value);
      });
    }

    test('the invalid tag 0 means no rotation', () {
      final header = parseImageHeader(
        BytesSource(jpegWith(40, 20, orientation: 0)),
      )!;

      expect(header.orientation, 1);
    });

    test('values above 8 mean no rotation', () {
      for (final value in [9, 15, 255, 65535]) {
        expect(normalizeOrientation(value), 1, reason: '$value');
      }
    });

    test('no tag means no rotation', () {
      expect(parseImageHeader(BytesSource(jpegWith(40, 20)))!.orientation, 1);
      expect(normalizeOrientation(null), 1);
    });

    test('both byte orders of the EXIF block', () {
      expect(readExifOrientation(exifPayload(6, little: true)), 6);
      expect(readExifOrientation(exifPayload(8, little: false)), 8);
    });

    test('garbage in the EXIF block never throws', () {
      expect(readExifOrientation(Uint8List(0)), isNull);
      expect(readExifOrientation(Uint8List(40)), isNull);
      final bad = exifPayload(6, little: true)..[10] = 0x7F;
      expect(readExifOrientation(bad), isNull);
      final cut = exifPayload(6, little: true).sublist(0, 20);
      expect(readExifOrientation(cut), isNull);
    });
  });

  group('the size is the stored pixels, never the EXIF size tags', () {
    test('false ExifImageWidth/Height are ignored (Xiaomi: 1840x4080 for a '
        '972x1260 file)', () {
      final image = img.Image(width: 972, height: 1260);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      image.exif.exifIfd[0xA002] = img.IfdValueShort(1840); // ExifImageWidth
      image.exif.exifIfd[0xA003] = img.IfdValueShort(4080); // ExifImageHeight
      image.exif.imageIfd.orientation = 6;
      final bytes = img.encodeJpg(image);

      final header = parseImageHeader(BytesSource(bytes))!;

      expect(header.width, 972);
      expect(header.height, 1260);
      expect(header.orientation, 6);
    });
  });
}
