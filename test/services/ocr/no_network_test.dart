import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The OCR runs fully on the phone (ADR-001). These checks read the source:
/// the OCR code and the modules next to it must not import an HTTP client or
/// open a socket.
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

  test('the Android manifest asks for no network permission', () {
    final manifest = File('$root/android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    expect(manifest, isNot(contains('android.permission.INTERNET')));
  });
}
