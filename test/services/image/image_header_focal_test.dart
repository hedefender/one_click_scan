import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:one_click_scan/services/image/image_header_parser.dart';

/// `Exif\0\0` + a TIFF block: IFD0 with one entry (0x8769, the Exif IFD), and
/// that IFD with one entry 0xA405 = [focal] (SHORT, or LONG when [asLong]).
Uint8List focalPayload(int focal, {required bool little, bool asLong = false}) {
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
  u32(8); // IFD0 at offset 8
  u16(1);
  u16(0x8769);
  u16(4); // LONG
  u32(1);
  u32(26); // the Exif IFD at offset 26: 8 + 2 + 12 + 4
  u32(0); // no next IFD
  u16(1);
  u16(0xA405);
  u16(asLong ? 4 : 3);
  u32(1);
  if (asLong) {
    u32(focal);
  } else {
    u16(focal);
    u16(0);
  }
  u32(0);
  return b.toBytes();
}

void main() {
  group('35 mm focal length from the EXIF block', () {
    test('both byte orders, SHORT and LONG', () {
      for (final little in [true, false]) {
        expect(
          readExifFocalLength35mm(focalPayload(26, little: little)),
          26,
          reason: 'little=$little',
        );
        expect(
          readExifFocalLength35mm(
            focalPayload(70, little: little, asLong: true),
          ),
          70,
          reason: 'long, little=$little',
        );
      }
    });

    test('0, an absurd value and no EXIF give null', () {
      expect(readExifFocalLength35mm(focalPayload(0, little: true)), isNull);
      expect(readExifFocalLength35mm(focalPayload(9000, little: true)), isNull);
      expect(readExifFocalLength35mm(Uint8List(0)), isNull);
      expect(readExifFocalLength35mm(Uint8List(40)), isNull);
    });

    test('a truncated block never throws', () {
      final full = focalPayload(26, little: true);
      for (var n = 0; n < full.length; n++) {
        expect(
          () => readExifFocalLength35mm(Uint8List.sublistView(full, 0, n)),
          returnsNormally,
        );
      }
    });

    test('the header of a JPEG carries it, and null when there is none', () {
      final image = img.Image(width: 64, height: 48);
      img.fill(image, color: img.ColorRgb8(200, 200, 200));
      image.exif.exifIfd.data[0xA405] = img.IfdValueShort(26);
      final withFocal = parseImageHeader(BytesSource(img.encodeJpg(image)))!;
      expect(withFocal.focalLength35mm, 26);

      final plain = img.Image(width: 64, height: 48);
      final without = parseImageHeader(BytesSource(img.encodeJpg(plain)))!;
      expect(without.focalLength35mm, isNull);
    });
  });
}
