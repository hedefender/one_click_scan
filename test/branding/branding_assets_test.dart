import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Reads the generated launcher icon and splash files (made by
/// `tool/generate_branding.dart`) and checks the rules they must keep.
void main() {
  const res = 'android/app/src/main/res';
  const densities = <String, double>{
    'mdpi': 1.0,
    'hdpi': 1.5,
    'xhdpi': 2.0,
    'xxhdpi': 3.0,
    'xxxhdpi': 4.0,
  };

  img.Image read(String path) {
    final image = img.decodePng(File(path).readAsBytesSync());
    expect(image, isNotNull, reason: '$path is not a readable PNG');
    return image!;
  }

  group('adaptive icon foreground', () {
    for (final entry in densities.entries) {
      group(entry.key, () {
        final size = (108 * entry.value).round();
        late img.Image foreground;

        setUp(() {
          foreground = read(
            '$res/drawable-${entry.key}/ic_launcher_foreground.png',
          );
        });

        test('is the 108dp canvas with a real alpha channel', () {
          expect(foreground.width, size);
          expect(foreground.height, size);
          expect(foreground.numChannels, 4);
          expect(foreground.hasAlpha, isTrue);
        });

        test('has transparent corners', () {
          final last = size - 1;
          for (final (x, y) in [(0, 0), (last, 0), (0, last), (last, last)]) {
            expect(foreground.getPixel(x, y).a, 0, reason: 'corner $x,$y');
          }
        });

        test('keeps every opaque pixel inside the 66dp safe zone', () {
          final limit = size * 66 / 108 / 2;
          var opaque = 0;
          var farthest = 0.0;
          for (final pixel in foreground) {
            if (pixel.a < 128) continue;
            opaque++;
            final dx = pixel.x + 0.5 - size / 2;
            final dy = pixel.y + 0.5 - size / 2;
            farthest = math.max(farthest, math.sqrt(dx * dx + dy * dy));
          }
          expect(opaque, greaterThan(size * size ~/ 10), reason: 'too small');
          expect(farthest, lessThanOrEqualTo(limit));
          // Not shrunk more than needed: it should use most of the zone.
          expect(farthest, greaterThan(limit * 0.95));
        });

        test('is centred', () {
          var minX = size, maxX = 0, minY = size, maxY = 0;
          for (final pixel in foreground) {
            if (pixel.a < 128) continue;
            minX = math.min(minX, pixel.x);
            maxX = math.max(maxX, pixel.x);
            minY = math.min(minY, pixel.y);
            maxY = math.max(maxY, pixel.y);
          }
          final centreX = (minX + maxX) / 2, centreY = (minY + maxY) / 2;
          expect((centreX - size / 2).abs(), lessThan(size * 0.05));
          expect((centreY - size / 2).abs(), lessThan(size * 0.05));
        });

        test('has no green fringe on its soft edges', () {
          // Below alpha 32 a pixel is invisible, and its colour is only
          // rounding noise of the un-premultiply step. The yellow-green sparks
          // are real colour (spill up to ~50); the keyed background is ~240.
          for (final pixel in foreground) {
            if (pixel.a < 32 || pixel.a == 255) continue;
            final spill = pixel.g - math.max(pixel.r, pixel.b);
            expect(
              spill,
              lessThan(70),
              reason: 'green edge at ${pixel.x},${pixel.y}',
            );
          }
        });
      });
    }

    test('only has the symbol: the green background is gone', () {
      final foreground = read(
        '$res/drawable-xxxhdpi/ic_launcher_foreground.png',
      );
      var green = 0;
      for (final pixel in foreground) {
        if (pixel.a < 32) continue;
        if (pixel.g - math.max(pixel.r, pixel.b) > 150) green++;
      }
      expect(green, 0);
    });
  });

  group('adaptive icon resources', () {
    test('the background is an image-free radial gradient', () {
      final xml = File('$res/drawable/ic_launcher_background.xml')
          .readAsStringSync();

      expect(xml, contains('android:type="radial"'));
      expect(xml, isNot(contains('@drawable/')));
      expect(xml, isNot(contains('@mipmap/')));
    });

    test('the adaptive icon uses the background and the foreground', () {
      final xml = File('$res/mipmap-anydpi-v26/ic_launcher.xml')
          .readAsStringSync();

      expect(xml, contains('@drawable/ic_launcher_background'));
      expect(xml, contains('@drawable/ic_launcher_foreground'));
    });

    test('the manifest points at the launcher icon', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();

      expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    });
  });

  group('legacy launcher icon', () {
    for (final entry in densities.entries) {
      test('${entry.key} is a ${(48 * entry.value).round()}px opaque icon', () {
        final size = (48 * entry.value).round();
        final icon = read('$res/mipmap-${entry.key}/ic_launcher.png');

        expect(icon.width, size);
        expect(icon.height, size);
        expect(icon.getPixel(size ~/ 2, size ~/ 2).a, 255);
      });
    }
  });

  group('splash', () {
    final colors = File('$res/values/colors.xml').readAsStringSync();
    final background = RegExp(r'name="splash_background">#([0-9A-Fa-f]{6})<')
        .firstMatch(colors)!
        .group(1)!;
    final backgroundRgb = [
      for (var i = 0; i < 6; i += 2)
        int.parse(background.substring(i, i + 2), radix: 16),
    ];

    for (final entry in densities.entries) {
      group(entry.key, () {
        final size = (288 * entry.value).round();
        late img.Image icon;

        setUp(() {
          icon = read('$res/drawable-${entry.key}/splash_icon.png');
        });

        test('is the 288dp canvas', () {
          expect(icon.width, size);
          expect(icon.height, size);
        });

        test('shows nothing outside the 192dp circle of Android 12', () {
          final limit = size * 192 / 288 / 2;
          for (final pixel in icon) {
            if (pixel.a == 0) continue;
            final dx = pixel.x + 0.5 - size / 2;
            final dy = pixel.y + 0.5 - size / 2;
            expect(
              math.sqrt(dx * dx + dy * dy),
              lessThanOrEqualTo(limit + 1),
              reason:
                  'visible pixel outside the circle at ${pixel.x},${pixel.y}',
            );
          }
        });

        test('fades into the splash background colour at the circle', () {
          // On the horizontal axis, where the image is only the frame around
          // the plate, just inside the circle.
          final x = (size / 2 + size * 0.30).round();
          final pixel = icon.getPixel(x, size ~/ 2);
          expect(pixel.a, greaterThan(0));
          expect((pixel.r - backgroundRgb[0]).abs(), lessThan(6));
          expect((pixel.g - backgroundRgb[1]).abs(), lessThan(6));
          expect((pixel.b - backgroundRgb[2]).abs(), lessThan(6));
        });

        test('shows the whole icon in the middle', () {
          expect(icon.getPixel(size ~/ 2, size ~/ 2).a, 255);
        });
      });
    }

    test('both themes use the splash icon and colour on Android 12+', () {
      for (final folder in ['values-v31', 'values-night-v31']) {
        final xml = File('$res/$folder/styles.xml').readAsStringSync();

        expect(xml, contains('windowSplashScreenAnimatedIcon'));
        expect(xml, contains('@drawable/splash_icon'));
        expect(xml, contains('@color/splash_background'));
      }
    });

    test('the window background before Android 12 centres the icon', () {
      for (final folder in ['drawable', 'drawable-v21']) {
        final xml = File('$res/$folder/launch_background.xml')
            .readAsStringSync();

        expect(xml, contains('@color/splash_background'));
        expect(xml, contains('@drawable/splash_icon'));
        expect(xml, contains('android:gravity="center"'));
      }
    });
  });
}
