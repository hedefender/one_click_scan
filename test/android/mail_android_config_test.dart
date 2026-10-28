import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Android side of the mail layer, read from the sources: the password
/// must not travel in a backup (ADR-021), the share intent has to carry what the
/// tests of the integration folder expect, and the two copies of the Kotlin
/// handler must be the same file.
void main() {
  final root = Directory.current.path;
  String read(String path) => File('$root/$path').readAsStringSync();

  group('backups', () {
    final manifest = read('android/app/src/main/AndroidManifest.xml');

    test('the app is excluded from Android backups', () {
      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:fullBackupContent="false"'));
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
    });

    test('the data extraction rules exclude everything, for cloud backup and '
        'for device transfer', () {
      final rules = read(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      );
      for (final section in ['cloud-backup', 'device-transfer']) {
        final start = rules.indexOf('<$section>');
        final end = rules.indexOf('</$section>');
        expect(start, greaterThan(-1), reason: section);
        final body = rules.substring(start, end);
        for (final domain in ['root', 'file', 'database', 'sharedpref']) {
          expect(
            body,
            contains('<exclude domain="$domain"'),
            reason: '$section $domain',
          );
        }
        expect(body, isNot(contains('<include')));
      }
    });

    test('package visibility: the three mail apps and one mailto intent, and '
        'no permission to see every app', () {
      expect(manifest, isNot(contains('QUERY_ALL_PACKAGES')));
      final queries = manifest.substring(
        manifest.indexOf('<queries>'),
        manifest.indexOf('</queries>'),
      );
      for (final package in [
        'com.google.android.gm',
        'com.microsoft.office.outlook',
        'com.yahoo.mobile.client.android.mail',
      ]) {
        expect(queries, contains('<package android:name="$package" />'));
      }
      expect(queries, contains('android.intent.action.SENDTO'));
      expect(queries, contains('android:scheme="mailto"'));
    });

    test('INTERNET is asked for, and nothing else about the network', () {
      expect(manifest, contains('android.permission.INTERNET'));
      expect(manifest, isNot(contains('ACCESS_NETWORK_STATE')));
    });
  });

  group('the Kotlin handler', () {
    final kotlin = read(
      'android/app/src/main/kotlin/com/example/one_click_scan/ScanFilesHandler.kt',
    );

    test('the overlay copy is the same file', () {
      expect(
        read(
          'android_overlay/app/src/main/kotlin/com/example/one_click_scan/ScanFilesHandler.kt',
        ),
        kotlin,
      );
    });

    test('the share intent: ACTION_SEND, e-mail, subject, text, the stream '
        'and the read grant on the intent and on the clip', () {
      for (final needle in [
        'Intent(Intent.ACTION_SEND)',
        'Intent.EXTRA_EMAIL',
        'Intent.EXTRA_SUBJECT',
        'Intent.EXTRA_TEXT',
        'Intent.EXTRA_STREAM',
        'ClipData.newRawUri',
        'Intent.FLAG_GRANT_READ_URI_PERMISSION',
      ]) {
        expect(kotlin, contains(needle), reason: needle);
      }
      // The intent is read-only: no write grant.
      expect(
        kotlin,
        isNot(contains('addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION')),
      );
    });

    test('the methods the Dart side calls exist', () {
      for (final method in [
        'shareDocument',
        'describeShare',
        'copyUriToFile',
        'openDocument',
        'findMailApps',
        'openLink',
      ]) {
        expect(kotlin, contains('"$method"'), reason: method);
      }
    });

    test('the routes: an explicit package, a chooser of the mail apps, the '
        'generic menu last, and a read grant for the package', () {
      for (final needle in [
        'setPackage(targetPackage)',
        'route == "provider" || route == "mail"',
        'route == "chooser"',
        'EXTRA_INITIAL_INTENTS',
        'grantUriPermission',
        'Intent.createChooser(buildShareIntent(call, null), null)',
        'Intent.ACTION_SENDTO',
        'mailto:',
      ]) {
        expect(kotlin, contains(needle), reason: needle);
      }
    });

    test('discard (ADR-027): delete by URI, only inside what was granted', () {
      for (final method in [
        'deleteDocument',
        'saveToGallery',
        'deleteGalleryItem',
      ]) {
        expect(kotlin, contains('"$method"'), reason: method);
      }
      // A document is deleted only under a folder the user granted, and an
      // already deleted one counts as deleted.
      expect(kotlin, contains('persistedUriPermissions.any'));
      expect(kotlin, contains('startsWith(it.uri.toString() + "/")'));
      expect(kotlin, contains('DocumentsContract.deleteDocument'));
      expect(kotlin, contains('java.io.FileNotFoundException'));
      // A Gallery entry is deleted only if it is a MediaStore image URI, by the
      // exact URI, never by a query on a name or a folder.
      expect(kotlin, contains('MediaStore.Images.Media.EXTERNAL_CONTENT_URI'));
      expect(kotlin, contains('contentResolver.delete(uri, null, null)'));
      expect(kotlin, isNot(contains('DISPLAY_NAME + " =')));
      expect(kotlin, isNot(contains('selection')));
      expect(kotlin, isNot(contains('LIKE')));
    });

    test('the Gallery copy: pending while written, then visible', () {
      expect(kotlin, contains('MediaStore.Images.Media.IS_PENDING'));
      expect(kotlin, contains('RELATIVE_PATH'));
      expect(kotlin, contains('Environment.DIRECTORY_PICTURES'));
      // A half written entry is removed again.
      expect(kotlin, contains('Never leave a half entry in the Gallery'));
    });

    test('no new permission for Phase 5: the storage permission is the one '
        'that was already declared, for Android 10 and older', () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      final permissions = RegExp(r'<uses-permission[^>]*android:name="([^"]+)"')
          .allMatches(manifest)
          .map((m) => m.group(1))
          .toSet();
      expect(permissions, {
        'android.permission.CAMERA',
        'android.permission.INTERNET',
        'android.permission.WRITE_EXTERNAL_STORAGE',
      });
    });

    test('a link opens only if it is https, as a browsable view', () {
      expect(kotlin, contains('uri.scheme != "https"'));
      expect(kotlin, contains('Intent.ACTION_VIEW, uri'));
      expect(kotlin, contains('Intent.CATEGORY_BROWSABLE'));
    });

    test('no mail address or text of a message is logged natively', () {
      expect(kotlin, isNot(contains('Log.')));
    });
  });
}
