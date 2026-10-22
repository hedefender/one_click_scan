import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'paddle_config.dart';
import 'paddle_pixels.dart';

/// Decodes with Flutter's native codec, down-scaled while decoding when the
/// image is larger than [maxSide]. Root isolate only (`dart:ui`). Returns
/// RGBA pixels (stride 4); the stages are charged to [t].
Future<Pixels> decodeNative(String path, int maxSide, StageTimer t) async {
  final bytes = await File(path).readAsBytes();
  t.lap('read');
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  int? targetW, targetH;
  if (maxSide > 0 && math.max(descriptor.width, descriptor.height) > maxSide) {
    if (descriptor.width >= descriptor.height) {
      targetW = maxSide;
    } else {
      targetH = maxSide;
    }
  }
  final codec = await descriptor.instantiateCodec(
    targetWidth: targetW,
    targetHeight: targetH,
  );
  final frame = await codec.getNextFrame();
  final image = frame.image;
  t.lap('decode');
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final pixels = Pixels(
    data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    image.width,
    image.height,
    4,
  );
  image.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();
  t.lap('toRgba');
  return pixels;
}
