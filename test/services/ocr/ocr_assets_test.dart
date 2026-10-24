import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/ocr/ocr_language_pack_registry.dart';

import '../../../tool/ocr_models.dart' as tool;

void main() {
  final root = Directory.current.path;

  test('the bundled models are present and match their SHA-256', () {
    final problems = tool.verifyAll(root);

    expect(
      problems,
      isEmpty,
      reason:
          'OCR models are missing or wrong: ${problems.join('; ')}. '
          'Run tool/fetch_ocr_models.sh (it downloads and verifies them).',
    );
  });

  test('assets/ocr/manifest.json says what the pack registry says', () {
    final manifest = jsonDecode(
      File('$root/assets/ocr/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final files = {
      for (final f in manifest['files'] as List)
        (f as Map<String, dynamic>)['name'] as String: f,
    };
    final registry = OcrLanguagePackRegistry.standard;
    final expected = [
      registry.detector,
      for (final p in registry.bundled) ...[p.model, p.dictionary],
    ];

    expect(files.keys.toSet(), expected.map((f) => f.name).toSet());
    for (final f in expected) {
      final entry = files[f.name] as Map<String, dynamic>;
      expect(entry['sha256'], f.sha256, reason: f.name);
      expect(entry['bytes'], f.bytes, reason: f.name);
    }
  });

  test('every manifest URL is pinned to a commit, not to a moving branch', () {
    for (final f in tool.readManifest(root)) {
      expect(f.url, startsWith('https://'), reason: f.name);
      expect(f.url, isNot(contains('/main/')), reason: f.name);
      expect(f.url, matches(RegExp(r'/resolve/[0-9a-f]{40}/')), reason: f.name);
    }
  });

  test('the fetch script exists and calls the verifier', () {
    final script = File('$root/tool/fetch_ocr_models.sh').readAsStringSync();

    expect(script, contains('tool/ocr_models.dart'));
  });

  test('the Gradle build refuses to package missing or wrong models', () {
    final gradle = File('$root/android/app/build.gradle.kts')
        .readAsStringSync();

    expect(gradle, contains('verifyOcrModels'));
    expect(gradle, contains('fetch_ocr_models.sh'));
  });
}
