import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../domain/lighting/light_metric.dart';
import 'detection.dart';
import 'flatten_light.dart';

/// Work order of the light correction. Plain values, sendable to an isolate.
class EnhanceJob {
  const EnhanceJob({
    required this.source,
    required this.target,
    required this.jpegQuality,
  });

  final String source;
  final String target;
  final int jpegQuality;
}

/// Decodes [EnhanceJob.source], removes the shadow (`flat`) and writes a JPEG.
/// True when the file was written. Never throws; a half-written target is
/// removed again. Synchronous so a test can call it directly.
bool enhanceLightSync(EnhanceJob job) {
  try {
    var image = img.decodeJpg(File(job.source).readAsBytesSync());
    if (image == null) return false;
    if (image.numChannels != 3) image = image.convert(numChannels: 3);
    final frame = RgbFrame(
      image.width,
      image.height,
      image.getBytes(order: img.ChannelOrder.rgb),
    );
    final flat = flattenLight(frame);
    final jpeg = img.encodeJpg(
      img.Image.fromBytes(
        width: flat.width,
        height: flat.height,
        bytes: flat.rgb.buffer,
        numChannels: 3,
      ),
      quality: job.jpegQuality,
    );
    File(job.target).writeAsBytesSync(jpeg);
    return true;
  } catch (_) {
    try {
      final file = File(job.target);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // The cache is purged at the next start-up anyway.
    }
    return false;
  }
}

/// The metric of a small JPEG file (the reduced shot). Null when unreadable.
LightMetric? measureJpegSync(String path) {
  try {
    final image = img.decodeJpg(File(path).readAsBytesSync());
    if (image == null) return null;
    return metricOfImage(image);
  } catch (_) {
    return null;
  }
}

/// Y (luma) metric of a decoded picture, on every pixel (it is small).
LightMetric? metricOfImage(img.Image image) {
  final rgb = image
      .convert(numChannels: 3)
      .getBytes(order: img.ChannelOrder.rgb);
  final n = image.width * image.height;
  final y = Uint8List(n);
  for (var i = 0, j = 0; i < n; i++, j += 3) {
    y[i] = (rgb[j] * 299 + rgb[j + 1] * 587 + rgb[j + 2] * 114) ~/ 1000;
  }
  return LightMetric.fromLuma(y, width: image.width, height: image.height);
}
