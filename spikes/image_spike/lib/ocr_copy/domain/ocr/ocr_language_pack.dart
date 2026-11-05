import 'package:equatable/equatable.dart';

/// Where the files of a pack come from.
enum OcrPackAvailability {
  /// Shipped inside the APK.
  bundled,

  /// Fetched on request. Not offered yet (future work, no network code in the
  /// OCR layer); the registry can already describe such packs.
  downloadable,
}

/// One file of a pack, identified by its content.
class OcrModelFile extends Equatable {
  const OcrModelFile({
    required this.name,
    required this.sha256,
    required this.bytes,
  });

  /// File name, for example `rec_greek.onnx`.
  final String name;

  /// Lower-case hex SHA-256 of the file.
  final String sha256;
  final int bytes;

  @override
  List<Object?> get props => [name, sha256, bytes];
}

/// A recognition model with its character dictionary. The detector is shared
/// by every pack (see [OcrLanguagePackRegistry.detector]).
class OcrLanguagePack extends Equatable {
  const OcrLanguagePack({
    required this.id,
    required this.languageCodes,
    required this.model,
    required this.dictionary,
    this.availability = OcrPackAvailability.bundled,
  });

  /// Stable id, also the persisted choice (`greek`, `latin`).
  final String id;

  /// BCP 47 codes of the languages the pack is meant for. The wording shown to
  /// the user is in the localised strings.
  final List<String> languageCodes;
  final OcrModelFile model;
  final OcrModelFile dictionary;
  final OcrPackAvailability availability;

  bool get isBundled => availability == OcrPackAvailability.bundled;

  @override
  List<Object?> get props => [
    id,
    languageCodes,
    model,
    dictionary,
    availability,
  ];
}
