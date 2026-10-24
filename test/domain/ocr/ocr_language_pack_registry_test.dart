import 'package:flutter_test/flutter_test.dart';
import 'package:one_click_scan/domain/ocr/ocr_language_pack.dart';
import 'package:one_click_scan/domain/ocr/ocr_language_pack_registry.dart';

void main() {
  final registry = OcrLanguagePackRegistry.standard;

  test('the app ships exactly the greek and latin packs', () {
    expect(registry.bundled.map((p) => p.id), ['greek', 'latin']);
    expect(registry.packs.every((p) => p.isBundled), isTrue);
  });

  test('greek pack reads el and en, latin reads en and accented languages', () {
    expect(registry.byId('greek')!.languageCodes, containsAll(['el', 'en']));
    expect(
      registry.byId('latin')!.languageCodes,
      containsAll(['en', 'de', 'fr', 'es', 'it', 'pt']),
    );
    expect(registry.byId('latin')!.languageCodes, isNot(contains('el')));
  });

  test('byId is null for an unknown id', () {
    expect(registry.byId('klingon'), isNull);
    expect(registry.byId(null), isNull);
  });

  group('default from the device language', () {
    test('Greek device: greek pack', () {
      expect(registry.defaultFor('el').id, OcrPackIds.greek);
    });

    test('every other language: latin pack', () {
      for (final code in ['en', 'de', 'fr', 'ru', '']) {
        expect(registry.defaultFor(code).id, OcrPackIds.latin, reason: code);
      }
    });
  });

  group('resolve (a stored choice wins when it is valid)', () {
    test('a stored bundled id is kept whatever the device language', () {
      expect(registry.resolve('latin', 'el').id, 'latin');
      expect(registry.resolve('greek', 'en').id, 'greek');
    });

    test('nothing stored or an unknown id falls back to the default', () {
      expect(registry.resolve(null, 'el').id, 'greek');
      expect(registry.resolve('', 'en').id, 'latin');
      expect(registry.resolve('klingon', 'el').id, 'greek');
    });
  });

  group('a registry can hold packs that are not in the APK', () {
    const model = OcrModelFile(name: 'rec_eslav.onnx', sha256: 'aa', bytes: 1);
    const dict = OcrModelFile(name: 'dict_eslav.txt', sha256: 'bb', bytes: 1);
    final extended = OcrLanguagePackRegistry(
      detector: registry.detector,
      packs: [
        ...registry.packs,
        const OcrLanguagePack(
          id: 'eslav',
          languageCodes: ['ru', 'uk', 'be', 'en'],
          model: model,
          dictionary: dict,
          availability: OcrPackAvailability.downloadable,
        ),
      ],
    );

    test('it is known but not offered as bundled', () {
      expect(extended.byId('eslav'), isNotNull);
      expect(extended.byId('eslav')!.isBundled, isFalse);
      expect(extended.bundled.map((p) => p.id), ['greek', 'latin']);
    });

    test('a stored downloadable id is not used until it is installed', () {
      expect(extended.resolve('eslav', 'el').id, 'greek');
    });
  });

  test('model hashes are 64 hex characters', () {
    final all = [
      registry.detector,
      for (final p in registry.packs) ...[p.model, p.dictionary],
    ];
    for (final f in all) {
      expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')), reason: f.name);
      expect(f.bytes, greaterThan(0));
    }
  });
}
