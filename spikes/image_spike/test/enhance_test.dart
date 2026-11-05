import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_spike/src/detect/detection.dart';
import 'package:image_spike/src/image/enhance.dart';

/// White paper with a dark band of "text" and a shadow on the right half.
RgbFrame _page({required bool shadow}) {
  const w = 200, h = 100;
  final b = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = 240.0;
      if (shadow && x >= 100) v *= 0.5;
      if (y >= 45 && y < 50 && x % 20 < 10) v *= 0.3; // ink
      final i = (y * w + x) * 3;
      b[i] = b[i + 1] = b[i + 2] = v.round();
    }
  }
  return RgbFrame(w, h, b);
}

int _px(RgbFrame f, int x, int y) => f.rgb[(y * f.width + x) * 3];

void main() {
  test('flattenLight makes paper in light and in shadow equally white', () {
    final out = flattenLight(_page(shadow: true));
    expect(_px(out, 20, 10), greaterThan(235));
    expect(_px(out, 160, 10), greaterThan(235));
    expect(_px(out, 5, 46), lessThan(120)); // ink stays dark
  });

  test('binarize keeps ink black and paper white, also in shadow', () {
    final out = binarize(flattenLight(_page(shadow: true)));
    expect(_px(out, 5, 46), 0);
    expect(_px(out, 165, 46), 0);
    expect(_px(out, 20, 10), 255);
    expect(_px(out, 160, 10), 255);
  });

  test('clahe and gray keep the size and the order of dark and light', () {
    final f = _page(shadow: false);
    final c = clahe(f);
    expect(c.rgb.length, f.rgb.length);
    expect(_px(c, 5, 46), lessThan(_px(c, 20, 10)));
    final g = toGray(f);
    expect(g.rgb[0], g.rgb[1]);
  });
}
