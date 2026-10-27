import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/entities/pdf_page_input.dart';
import 'package:one_click_scan/domain/mail/share_route.dart';
import 'package:one_click_scan/domain/ports/attachment_source.dart';
import 'package:one_click_scan/domain/ports/draft_sharer.dart';
import 'package:one_click_scan/services/mail/android_mail_channels.dart';
import 'package:one_click_scan/services/scan_files/android_scan_file_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(mailChannelName);
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

  const pdf = StoredPdf(
    fileName: '2026-10-21_19-05-12.pdf',
    uri: 'content://x/doc/1',
    pageCount: 1,
    textPageCount: 1,
    byteSize: 10,
  );

  test('the mail adapters use the channel of ScanFilesHandler.kt', () {
    expect(mailChannelName, AndroidScanFileStore.channelName);
    expect(mailChannelName, 'com.example.one_click_scan/scan_files');
  });

  group('AndroidAttachmentSource', () {
    late Directory dir;
    late AndroidAttachmentSource source;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('attach_test');
      source = AndroidAttachmentSource(
        directory: Directory('${dir.path}/mail_work'),
      );
    });

    tearDown(() => dir.delete(recursive: true));

    test('asks the native side to copy the document URI to a file in its '
        'folder, and returns it as a PDF attachment', () async {
      reply((call) {
        File(call.arguments['targetPath'] as String)
            .writeAsBytesSync([37, 80, 68, 70]);
        return null;
      });

      final attachment = await source.prepare(pdf);

      expect(calls.single.method, 'copyUriToFile');
      expect(calls.single.arguments['uri'], 'content://x/doc/1');
      expect(
        (calls.single.arguments['targetPath'] as String).replaceAll(r'\', '/'),
        startsWith('${dir.path.replaceAll(r'\', '/')}/mail_work/'),
      );
      expect(attachment.fileName, '2026-10-21_19-05-12.pdf');
      expect(attachment.mimeType, 'application/pdf');
      expect(File(attachment.path).readAsBytesSync(), [37, 80, 68, 70]);
    });

    test('a native error, or no file, is "unavailable"', () async {
      reply((_) => throw PlatformException(code: 'unreadable'));
      await expectLater(
        source.prepare(pdf),
        throwsA(isA<AttachmentUnavailable>()),
      );

      reply((_) => null); // the native side wrote nothing
      await expectLater(
        source.prepare(pdf),
        throwsA(isA<AttachmentUnavailable>()),
      );
    });

    test(
      'release deletes the copy, and never throws for a missing one',
      () async {
        reply((call) {
          File(call.arguments['targetPath'] as String).writeAsBytesSync([1]);
          return null;
        });
        final attachment = await source.prepare(pdf);

        await source.release(attachment);
        expect(File(attachment.path).existsSync(), isFalse);
        await source.release(attachment);
      },
    );

    test('purgeAll empties the folder', () async {
      reply((call) {
        File(call.arguments['targetPath'] as String).writeAsBytesSync([1]);
        return null;
      });
      final attachment = await source.prepare(pdf);

      await source.purgeAll();

      expect(File(attachment.path).existsSync(), isFalse);
    });
  });

  group('AndroidDraftSharer', () {
    final args = {
      'route': 'generic',
      'packages': <String>[],
      'to': ['inbox@example.com'],
      'subject': 'One Click Scan - 2026-10-21_19-05-12',
      'body': 'Document scanned with One Click Scan.',
      'uri': 'content://x/doc/1',
      'mimeType': 'application/pdf',
    };

    test('asks for ACTION_SEND with the recipient, subject, text and the '
        'document URI', () async {
      reply((_) => 'opened');

      final result = await AndroidDraftSharer().share(
        route: const GenericShareRoute(),
        to: const ['inbox@example.com'],
        subject: 'One Click Scan - 2026-10-21_19-05-12',
        body: 'Document scanned with One Click Scan.',
        documentUri: 'content://x/doc/1',
        mimeType: 'application/pdf',
      );

      expect(result, DraftShareResult.openedGeneric);
      expect(calls.single.method, 'shareDocument');
      expect(calls.single.arguments, args);
    });

    test('the answers of the native side', () async {
      Future<DraftShareResult> ask() => AndroidDraftSharer().share(
        route: const GenericShareRoute(),
        to: const [],
        subject: 's',
        body: 'b',
        documentUri: 'content://x/doc/1',
        mimeType: 'application/pdf',
      );
      reply((_) => 'no_app');
      expect(await ask(), DraftShareResult.noApp);
      reply((_) => 'failed');
      expect(await ask(), DraftShareResult.failed);
      reply((_) => 'something else');
      expect(await ask(), DraftShareResult.failed);
      reply((_) => throw PlatformException(code: 'x'));
      expect(await ask(), DraftShareResult.failed);
    });

    test(
      'with no plugin behind the channel it is a failure, not a crash',
      () async {
        expect(
          await AndroidDraftSharer().share(
            route: const GenericShareRoute(),
            to: const [],
            subject: 's',
            body: 'b',
            documentUri: 'u',
            mimeType: 'application/pdf',
          ),
          DraftShareResult.failed,
        );
      },
    );

    test('describe asks the handler what the intent carries', () async {
      reply((_) => <String, Object?>{'action': 'android.intent.action.SEND'});

      final described = await AndroidDraftSharer().describe(
        route: const GenericShareRoute(),
        to: const ['inbox@example.com'],
        subject: 's',
        body: 'b',
        documentUri: 'content://x/doc/1',
        mimeType: 'application/pdf',
      );

      expect(calls.single.method, 'describeShare');
      expect(described['action'], 'android.intent.action.SEND');
    });
  });

  group('AndroidDraftSharer routes', () {
    Future<DraftShareResult> shareVia(DraftShareRoute route) {
      return AndroidDraftSharer().share(
        route: route,
        to: const ['inbox@example.com'],
        subject: 's',
        body: 'b',
        documentUri: 'content://x/doc/1',
        mimeType: 'application/pdf',
      );
    }

    test('the app of the provider: the route and the package go to the '
        'native side', () async {
      reply((_) => 'opened');

      final result = await shareVia(
        const ProviderAppRoute('com.google.android.gm'),
      );

      expect(result, DraftShareResult.opened);
      expect(calls.single.arguments['route'], 'provider');
      expect(calls.single.arguments['packages'], ['com.google.android.gm']);
    });

    test('the only mail app, and a chooser of mail apps only', () async {
      reply((_) => 'opened');

      expect(
        await shareVia(const SingleMailAppRoute('a.mail')),
        DraftShareResult.opened,
      );
      expect(calls.last.arguments['route'], 'mail');
      expect(calls.last.arguments['packages'], ['a.mail']);

      expect(
        await shareVia(const MailAppChooserRoute(['a.mail', 'b.mail'])),
        DraftShareResult.opened,
      );
      expect(calls.last.arguments['route'], 'chooser');
      expect(calls.last.arguments['packages'], ['a.mail', 'b.mail']);
    });

    test('only the generic menu is "openedGeneric", so the screen can say '
        'no mail app was found', () async {
      reply((_) => 'opened');
      expect(
        await shareVia(const GenericShareRoute()),
        DraftShareResult.openedGeneric,
      );
      expect(calls.single.arguments['route'], 'generic');
      expect(calls.single.arguments['packages'], isEmpty);
    });

    test('a package that is not there is "no app"', () async {
      reply((_) => 'no_app');
      expect(
        await shareVia(const ProviderAppRoute('gone.app')),
        DraftShareResult.noApp,
      );
    });
  });

  group('AndroidMailAppFinder', () {
    test('asks for the package of the provider and reads the answer', () async {
      reply(
        (_) => <String, Object?>{
          'providerAppInstalled': true,
          'mailtoPackages': ['com.google.android.gm', 'b.mail'],
        },
      );

      final apps = await AndroidMailAppFinder().find(
        providerPackage: 'com.google.android.gm',
      );

      expect(calls.single.method, 'findMailApps');
      expect(
        calls.single.arguments['providerPackage'],
        'com.google.android.gm',
      );
      expect(apps.providerAppInstalled, isTrue);
      expect(apps.mailtoPackages, ['com.google.android.gm', 'b.mail']);
    });

    test('an error, no plugin or an odd answer is "nothing found"', () async {
      reply((_) => throw PlatformException(code: 'x'));
      var apps = await AndroidMailAppFinder().find();
      expect(apps.providerAppInstalled, isFalse);
      expect(apps.mailtoPackages, isEmpty);

      reply((_) => <String, Object?>{'mailtoPackages': 'not a list'});
      apps = await AndroidMailAppFinder().find();
      expect(apps.mailtoPackages, isEmpty);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      apps = await AndroidMailAppFinder().find();
      expect(apps.mailtoPackages, isEmpty);
    });
  });

  group('AndroidLinkOpener', () {
    test('sends the address to openLink and nothing else', () async {
      reply((_) => 'opened');

      final opened = await AndroidLinkOpener().open(
        'https://myaccount.google.com/apppasswords',
      );

      expect(opened, isTrue);
      expect(calls.single.method, 'openLink');
      expect(calls.single.arguments, {
        'url': 'https://myaccount.google.com/apppasswords',
      });
    });

    test('a failure, an error or no plugin is false', () async {
      reply((_) => 'failed');
      expect(await AndroidLinkOpener().open('https://x.example/a'), isFalse);
      reply((_) => throw PlatformException(code: 'x'));
      expect(await AndroidLinkOpener().open('https://x.example/a'), isFalse);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      expect(await AndroidLinkOpener().open('https://x.example/a'), isFalse);
    });
  });
}
