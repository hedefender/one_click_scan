import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/core/errors/app_exceptions.dart';
import 'package:one_click_scan/domain/entities/storage_folder.dart';
import 'package:one_click_scan/domain/ports/open_pdf.dart';
import 'package:one_click_scan/services/pdf/android_open_pdf.dart';
import 'package:one_click_scan/services/scan_files/android_scan_file_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(AndroidOpenPdf.channelName);
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

  test('both adapters use the channel of ScanFilesHandler.kt', () {
    expect(AndroidOpenPdf.channelName, AndroidScanFileStore.channelName);
    expect(AndroidOpenPdf.channelName, 'com.example.one_click_scan/scan_files');
  });

  group('AndroidOpenPdf', () {
    test(
      'asks for ACTION_VIEW of the document URI as application/pdf',
      () async {
        reply((_) => 'opened');

        final result = await AndroidOpenPdf().open('content://x/doc/1');

        expect(result, OpenPdfResult.opened);
        expect(calls.single.method, 'openDocument');
        expect(calls.single.arguments, {
          'uri': 'content://x/doc/1',
          'mimeType': 'application/pdf',
        });
      },
    );

    test('no_viewer: no app can show a PDF', () async {
      reply((_) => 'no_viewer');

      expect(
        await AndroidOpenPdf().open('content://x/doc/1'),
        OpenPdfResult.noViewer,
      );
    });

    test('failed and unknown replies are failures', () async {
      reply((_) => 'failed');
      expect(await AndroidOpenPdf().open('u'), OpenPdfResult.failed);

      reply((_) => 'something else');
      expect(await AndroidOpenPdf().open('u'), OpenPdfResult.failed);

      reply((_) => null);
      expect(await AndroidOpenPdf().open('u'), OpenPdfResult.failed);
    });

    test('a platform error does not throw', () async {
      reply((_) => throw PlatformException(code: 'boom'));

      expect(await AndroidOpenPdf().open('u'), OpenPdfResult.failed);
    });

    test('no handler on this platform does not throw', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      expect(await AndroidOpenPdf().open('u'), OpenPdfResult.failed);
    });
  });

  group('AndroidScanFileStore.deleteByUri', () {
    test('sends the URI to the native side and nothing else', () async {
      reply((_) => null);

      await AndroidScanFileStore().deleteByUri(
        'content://com.android.externalstorage.documents/tree/x/document/x%2Fa.jpg',
      );

      expect(calls.single.method, 'deleteDocument');
      expect(calls.single.arguments, {
        'uri': 'content://com.android.externalstorage.documents/tree/x/document/x%2Fa.jpg',
      });
    });

    test('a refusal is an error with the failure of the handler', () async {
      reply((_) => throw PlatformException(code: 'write_failed'));

      await expectLater(
        AndroidScanFileStore().deleteByUri('content://x/document/1'),
        throwsA(
          isA<ScanStoreException>().having(
            (e) => e.failure,
            'failure',
            ScanStoreFailure.writeFailed,
          ),
        ),
      );
    });

    test('a URI outside the granted folder is no_access', () async {
      reply((_) => throw PlatformException(code: 'no_access'));

      await expectLater(
        AndroidScanFileStore().deleteByUri('content://other/document/1'),
        throwsA(
          isA<ScanStoreException>().having(
            (e) => e.failure,
            'failure',
            ScanStoreFailure.noAccess,
          ),
        ),
      );
    });
  });

  group('AndroidScanFileStore.copyToFolder returns the document URI', () {
    const folder = StorageFolder(uri: 'content://tree/1', name: 'Scans');

    test('the URI comes from the platform', () async {
      reply((_) => 'content://tree/1/document/pdf%2Fa.pdf');

      final uri = await AndroidScanFileStore().copyToFolder(
        folder: folder,
        subfolder: 'pdf',
        fileName: 'a.pdf',
        mimeType: 'application/pdf',
        sourcePath: '/cache/a.pdf',
      );

      expect(uri, 'content://tree/1/document/pdf%2Fa.pdf');
      expect(calls.single.method, 'copyToFolder');
      expect(calls.single.arguments, {
        'treeUri': 'content://tree/1',
        'subfolder': 'pdf',
        'fileName': 'a.pdf',
        'mimeType': 'application/pdf',
        'sourcePath': '/cache/a.pdf',
      });
    });

    test('no URI in the reply is an error, not a null', () async {
      reply((_) => null);

      await expectLater(
        AndroidScanFileStore().copyToFolder(
          folder: folder,
          subfolder: 'pdf',
          fileName: 'a.pdf',
          mimeType: 'application/pdf',
          sourcePath: '/cache/a.pdf',
        ),
        throwsA(isA<ScanStoreException>()),
      );
    });

    test('the error codes of the handler keep their meaning', () async {
      for (final (code, failure) in [
        ('no_access', ScanStoreFailure.noAccess),
        ('exists', ScanStoreFailure.exists),
        ('write_failed', ScanStoreFailure.writeFailed),
        ('source_missing', ScanStoreFailure.sourceMissing),
      ]) {
        reply((_) => throw PlatformException(code: code));
        await expectLater(
          AndroidScanFileStore().copyToFolder(
            folder: folder,
            subfolder: 'pdf',
            fileName: 'a.pdf',
            mimeType: 'application/pdf',
            sourcePath: '/cache/a.pdf',
          ),
          throwsA(
            isA<ScanStoreException>().having(
              (e) => e.failure,
              'failure',
              failure,
            ),
          ),
        );
      }
    });
  });
}
