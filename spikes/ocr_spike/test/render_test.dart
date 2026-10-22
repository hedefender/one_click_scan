import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  exifProbe();
  test('copyRotate 270 + EXIF 6 bakes back to the original', () {
    final u = img.Image(width: 40, height: 20);
    img.fill(u, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(
      u,
      x1: 0,
      y1: 0,
      x2: 9,
      y2: 4,
      color: img.ColorRgb8(255, 0, 0),
    );
    final s = img.copyRotate(u, angle: 270);
    s.exif.imageIfd.orientation = 6;
    final back = img.bakeOrientation(
      img.decodeJpg(img.encodeJpg(s, quality: 100))!,
    );
    expect(back.width, 40);
    expect(back.getPixel(2, 2).r, greaterThan(200));
    expect(back.getPixel(2, 2).g, lessThan(60));
    expect(back.getPixel(35, 15).g, greaterThan(200));
  });
}

void exifProbe() {
  test('does package:image decodeImage already apply the EXIF orientation?', () {
    final u = img.Image(width: 40, height: 20);
    final s = img.copyRotate(u, angle: 270);
    s.exif.imageIfd.orientation = 6;
    final bytes = img.encodeJpg(s, quality: 90);
    final decoded = img.decodeImage(bytes)!;
    // ignore: avoid_print
    print(
      'stored ${s.width}x${s.height}, decoded ${decoded.width}x${decoded.height}, '
      'exif orientation ${decoded.exif.imageIfd.orientation}',
    );
  });
}
