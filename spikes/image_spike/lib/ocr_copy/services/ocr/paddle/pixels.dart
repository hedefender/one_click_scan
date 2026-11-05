import 'dart:typed_data';

/// Interleaved 8-bit pixels, [stride] bytes per pixel (3 = RGB, 4 = RGBA).
class Pixels {
  const Pixels(this.data, this.w, this.h, this.stride);

  final Uint8List data;
  final int w, h, stride;
}
