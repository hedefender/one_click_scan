import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:one_click_scan/domain/lighting/lighting_config.dart';
import 'package:one_click_scan/domain/ocr/ocr_cancellation.dart';
import 'package:one_click_scan/services/imaging/detection.dart';
import 'package:one_click_scan/services/imaging/flatten_light.dart';
import 'package:one_click_scan/services/imaging/isolate_light_enhancer.dart';
import 'package:one_click_scan/services/imaging/light_jobs.dart';

/// A synthetic thermal receipt: pale paper, faint grey ink, and a dark shadow
/// band across the lower part (the case where `flat` can lose letters).
img.Image thermalWithShadow({int w = 240, int h = 320}) {
  final image = img.Image(width: w, height: h, numChannels: 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final inShadow = y > h * 0.6;
      final paper = inShadow ? 90 : 225;
      var v = paper;
      // Faint text-like bars, ink only 30 levels under the paper.
      if (y % 24 > 14 && x > 20 && x < w - 20) v = paper - 30;
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return image;
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('light_jobs_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  String write(String name, img.Image image) {
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    file.writeAsBytesSync(img.encodeJpg(image, quality: 92));
    return file.path;
  }

  group('light metric of a small file', () {
    test('a dark synthetic shot is below the threshold', () {
      final dark = img.Image(width: 80, height: 100, numChannels: 3);
      img.fill(dark, color: img.ColorRgb8(60, 60, 60));
      final metric = measureJpegSync(write('dark.jpg', dark))!;
      expect(LightingConfig.isLowLight(metric), isTrue);
    });

    test('a bright synthetic shot is above it', () {
      final bright = img.Image(width: 80, height: 100, numChannels: 3);
      img.fill(bright, color: img.ColorRgb8(235, 235, 235));
      final metric = measureJpegSync(write('bright.jpg', bright))!;
      expect(LightingConfig.isLowLight(metric), isFalse);
    });

    test('an unreadable file is null, never an exception', () {
      final bad = File('${dir.path}${Platform.pathSeparator}bad.jpg')
        ..writeAsStringSync('not a jpeg');
      expect(measureJpegSync(bad.path), isNull);
      expect(measureJpegSync('${dir.path}/missing.jpg'), isNull);
    });
  });

  group('flat (shadow removal)', () {
    test('the shadow goes: the dark band becomes as bright as the rest', () {
      final image = thermalWithShadow();
      final frame = RgbFrame(
        image.width,
        image.height,
        image.getBytes(order: img.ChannelOrder.rgb),
      );
      final before = LightMetric5(frame);
      final after = LightMetric5(flattenLight(frame));
      expect(before.shadowLevel, lessThan(120));
      expect(after.shadowLevel, greaterThan(200));
    });

    test('the job writes a JPEG and never touches the source', () {
      final source = write('page.jpg', thermalWithShadow());
      final before = File(source).readAsBytesSync();
      final target = '${dir.path}${Platform.pathSeparator}flat.jpg';

      final done = enhanceLightSync(
        EnhanceJob(source: source, target: target, jpegQuality: 85),
      );

      expect(done, isTrue);
      expect(File(target).existsSync(), isTrue);
      expect(img.decodeJpg(File(target).readAsBytesSync()), isNotNull);
      // Byte for byte the same as before.
      expect(File(source).readAsBytesSync(), Uint8List.fromList(before));
    });

    test('an unreadable source gives false and no file', () {
      final bad = File('${dir.path}${Platform.pathSeparator}bad.jpg')
        ..writeAsStringSync('nope');
      final target = '${dir.path}${Platform.pathSeparator}out.jpg';
      expect(
        enhanceLightSync(
          EnhanceJob(source: bad.path, target: target, jpegQuality: 85),
        ),
        isFalse,
      );
      expect(File(target).existsSync(), isFalse);
    });
  });

  group('IsolateLightEnhancer (never the UI isolate)', () {
    test('writes the corrected picture from another isolate', () async {
      final source = write('page.jpg', thermalWithShadow());
      final target = '${dir.path}${Platform.pathSeparator}flat.jpg';

      final done = await const IsolateLightEnhancer().enhance(
        source: source,
        target: target,
        jpegQuality: 85,
        timeout: const Duration(seconds: 20),
      );

      expect(done, isTrue);
      expect(File(target).existsSync(), isTrue);
    });

    test('a cancel gives false and leaves no file', () async {
      final source = write('page.jpg', thermalWithShadow(w: 900, h: 1200));
      final target = '${dir.path}${Platform.pathSeparator}flat.jpg';
      final cancellation = OcrCancellation()..cancel();

      final done = await const IsolateLightEnhancer().enhance(
        source: source,
        target: target,
        jpegQuality: 85,
        timeout: const Duration(seconds: 20),
        cancellation: cancellation,
      );

      expect(done, isFalse);
      expect(File(target).existsSync(), isFalse);
    });

    test('a timeout kills the work and leaves no file', () async {
      final source = write('page.jpg', thermalWithShadow(w: 1600, h: 2200));
      final target = '${dir.path}${Platform.pathSeparator}flat.jpg';

      final done = await const IsolateLightEnhancer().enhance(
        source: source,
        target: target,
        jpegQuality: 85,
        timeout: const Duration(milliseconds: 1),
      );

      expect(done, isFalse);
      expect(File(target).existsSync(), isFalse);
    });
  });
}

/// Mean level of the lower (shadow) band of a frame.
class LightMetric5 {
  LightMetric5(RgbFrame frame) {
    var sum = 0;
    var n = 0;
    for (var y = (frame.height * 0.8).round(); y < frame.height; y++) {
      for (var x = 0; x < frame.width; x++) {
        sum += frame.rgb[(y * frame.width + x) * 3];
        n++;
      }
    }
    shadowLevel = sum / n;
  }

  late final double shadowLevel;
}
