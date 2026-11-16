import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/core/errors/app_exceptions.dart';
import 'package:one_click_scan/services/gallery/media_store_gallery_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(MediaStoreGalleryService.channelName);
  final calls = <MethodCall>[];

  void reply(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(calls.clear);
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('uses the channel of ScanFilesHandler.kt', () {
    expect(
      MediaStoreGalleryService.channelName,
      'io.github.hedefender.simpledocscan/scan_files',
    );
  });

  group('saveImage', () {
    test(
      'asks the native side to copy the picture and returns its URI',
      () async {
        reply((_) => 'content://media/external/images/media/42');

        final uri = await MediaStoreGalleryService().saveImage(
          'cache/1.jpg',
          fileName: 'scan_2026-10-21_01.jpg',
        );

        expect(uri, 'content://media/external/images/media/42');
        expect(calls.single.method, 'saveToGallery');
        expect(calls.single.arguments, {
          'sourcePath': 'cache/1.jpg',
          'fileName': 'scan_2026-10-21_01.jpg',
        });
      },
    );

    test('a native error is a GalleryException with the code only', () async {
      reply((_) => throw PlatformException(code: 'write_failed', message: 'x'));

      await expectLater(
        MediaStoreGalleryService().saveImage('cache/1.jpg', fileName: 'a.jpg'),
        throwsA(
          isA<GalleryException>().having(
            (e) => e.message,
            'message',
            'write_failed',
          ),
        ),
      );
    });

    test('an empty answer is a failure, not a URI', () async {
      reply((_) => '');

      await expectLater(
        MediaStoreGalleryService().saveImage('cache/1.jpg', fileName: 'a.jpg'),
        throwsA(isA<GalleryException>()),
      );
    });
  });

  group('deleteImage', () {
    test('sends the URI and nothing else', () async {
      reply((_) => null);

      await MediaStoreGalleryService().deleteImage(
        'content://media/external/images/media/42',
      );

      expect(calls.single.method, 'deleteGalleryItem');
      expect(calls.single.arguments, {
        'uri': 'content://media/external/images/media/42',
      });
    });

    test('a refusal is an error, never a silent success', () async {
      reply((_) => throw PlatformException(code: 'no_access'));

      await expectLater(
        MediaStoreGalleryService().deleteImage('content://media/x/1'),
        throwsA(isA<GalleryException>()),
      );
    });
  });
}
