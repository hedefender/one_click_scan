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
      ]) {
        expect(kotlin, contains('"$method"'), reason: method);
      }
    });

    test('no mail address or text of a message is logged natively', () {
      expect(kotlin, isNot(contains('Log.')));
    });
  });
}
