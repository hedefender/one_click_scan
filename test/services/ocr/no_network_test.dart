import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The OCR runs fully on the phone (ADR-001). These checks read the source:
/// the OCR code and the modules next to it must not import an HTTP client or
/// open a socket. Since Phase 4 the only code that uses the network is the mail
/// layer, `lib/services/mail/` (the last two tests).
void main() {
  final root = Directory.current.path;

  // Where OCR code lives: the services, the domain and the feature.
  final directories = [
    'lib/services/ocr',
    'lib/services/image',
    'lib/domain/ocr',
    'lib/domain/usecases',
    'lib/domain/ports',
    'lib/domain/entities',
    'lib/features/ocr',
  ];

  // \x27 is the single quote (the patterns are raw strings).
  final forbidden = <RegExp>[
    RegExp(
      r'import\s+\x27package:(http|dio|chopper|retrofit|web_socket_channel|'
      r'connectivity_plus|internet_connection_checker|firebase_[a-z_]*|'
      r'url_launcher)[/\x27]',
    ),
    RegExp(r'import\s+\x27dart:(html|cli)'),
    RegExp(r'\bHttpClient\b'),
    RegExp(r'\bSocket\b'),
    RegExp(r'\bWebSocket\b'),
    RegExp(r'\bHttpOverrides\b'),
    RegExp(r'https?://[a-z]'),
  ];

  Iterable<File> sources() sync* {
    for (final d in directories) {
      final dir = Directory('$root/$d');
      if (!dir.existsSync()) continue;
      for (final e in dir.listSync(recursive: true)) {
        if (e is File && e.path.endsWith('.dart')) yield e;
      }
    }
  }

  test('there is OCR code to check', () {
    expect(sources().length, greaterThan(20));
  });

  test('no OCR source file uses the network', () {
    final offenders = <String>[];
    for (final file in sources()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // A URL inside a comment is documentation, not a connection.
        if (line.trimLeft().startsWith('//')) continue;
        for (final pattern in forbidden) {
          if (pattern.hasMatch(line)) {
            offenders.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('the app depends on no network package in pubspec', () {
    final pubspec = File('$root/pubspec.yaml').readAsStringSync();
    final deps = pubspec.split('dev_dependencies:').first;

    for (final name in ['http:', 'dio:', 'chopper:', 'web_socket_channel:']) {
      expect(deps, isNot(contains('  $name')), reason: name);
    }
  });

  test('the manifest asks for INTERNET (the mail send) and no other network '
      'permission', () {
    final manifest = File('$root/android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    // Phase 4: the SMTP send of lib/services/mail needs the network. The OCR
    // checks above still guarantee that the OCR code does not use it.
    expect(manifest, contains('android.permission.INTERNET'));
    for (final other in [
      'ACCESS_NETWORK_STATE',
      'ACCESS_WIFI_STATE',
      'CHANGE_NETWORK_STATE',
    ]) {
      expect(manifest, isNot(contains('android.permission.$other')));
    }
  });

  test('only lib/services/mail uses a mail package or a socket', () {
    final offenders = <String>[];
    final mailPackage = RegExp(
      r'import\s+\x27package:(mailer|enough_mail)[/\x27]',
    );
    final socket = RegExp(r'\b(Socket|SecureSocket|HttpClient)\b');
    for (final e in Directory('$root/lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final path = e.path.replaceAll(r'\', '/');
      if (path.contains('/lib/services/mail/')) continue;
      for (final line in e.readAsLinesSync()) {
        if (line.trimLeft().startsWith('//')) continue;
        if (mailPackage.hasMatch(line) || socket.hasMatch(line)) {
          offenders.add(path);
          break;
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
