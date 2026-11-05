import 'ocr_language_pack.dart';

/// Ids of the packs that ship in the APK.
abstract final class OcrPackIds {
  static const greek = 'greek';
  static const latin = 'latin';
}

/// The packs the app knows about. Adding a downloadable pack later means
/// adding an entry with [OcrPackAvailability.downloadable]; nothing else in
/// the OCR code refers to a pack by name.
class OcrLanguagePackRegistry {
  OcrLanguagePackRegistry({
    required this.detector,
    required List<OcrLanguagePack> packs,
  }) : packs = List.unmodifiable(packs) {
    assert(
      packs.map((p) => p.id).toSet().length == packs.length,
      'duplicate pack id',
    );
    assert(packs.any((p) => p.isBundled), 'at least one bundled pack');
  }

  /// The detection model shared by all packs.
  final OcrModelFile detector;
  final List<OcrLanguagePack> packs;

  /// The pack list of this release. Hashes are those of
  /// `assets/ocr/manifest.json` (a test keeps the two in step).
  static final OcrLanguagePackRegistry standard = OcrLanguagePackRegistry(
    detector: const OcrModelFile(
      name: 'det_mobile.onnx',
      sha256:
          '1eb7b4f7ab657ebd1c66d5f79bca7497f29768a2e3c15e52daecbba1a8e4a039',
      bytes: 4826518,
    ),
    packs: const [
      OcrLanguagePack(
        id: OcrPackIds.greek,
        languageCodes: ['el', 'en'],
        model: OcrModelFile(
          name: 'rec_greek.onnx',
          sha256: '13373f736dbb229e96945fc41c2573403d91503b0775c7b7294839e0c5f3a7a3',
          bytes: 7791200,
        ),
        dictionary: OcrModelFile(
          name: 'dict_greek.txt',
          sha256: '31defc62c0c3ad3674a82da6192226a2ba98ef4ff014a7045cb88d59f9c3de31',
          bytes: 1103,
        ),
      ),
      OcrLanguagePack(
        id: OcrPackIds.latin,
        languageCodes: ['en', 'de', 'fr', 'es', 'it', 'pt'],
        model: OcrModelFile(
          name: 'rec_latin.onnx',
          sha256: '614ffc2d6d3902d360fad7f1b0dd455ee45e877069d14c4e51a99dc4ef144409',
          bytes: 7862832,
        ),
        dictionary: OcrModelFile(
          name: 'dict_latin.txt',
          sha256: '3c0a8a79b612653c25f765271714f71281e4e955962c153e272b7b8c1d2b13ff',
          bytes: 1634,
        ),
      ),
    ],
  );

  OcrLanguagePack? byId(String? id) {
    for (final pack in packs) {
      if (pack.id == id) return pack;
    }
    return null;
  }

  List<OcrLanguagePack> get bundled => [
    for (final pack in packs)
      if (pack.isBundled) pack,
  ];

  /// First-run choice: Greek when the device language is Greek, Latin
  /// otherwise.
  OcrLanguagePack defaultFor(String deviceLanguageCode) {
    final id = deviceLanguageCode == 'el' ? OcrPackIds.greek : OcrPackIds.latin;
    return byId(id) ?? bundled.first;
  }

  /// A stored choice if it names a known, bundled pack, else the default.
  /// (A stored id that no longer exists must not break the app.)
  OcrLanguagePack resolve(String? storedId, String deviceLanguageCode) {
    final stored = byId(storedId);
    if (stored != null && stored.isBundled) return stored;
    return defaultFor(deviceLanguageCode);
  }
}
