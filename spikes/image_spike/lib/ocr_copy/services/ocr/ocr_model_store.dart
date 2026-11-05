import 'dart:io';
import 'dart:typed_data';

import '../../domain/ocr/ocr_language_pack.dart';
import '../../domain/ocr/ocr_language_pack_registry.dart';

/// A bundled model could not be put on disk (the asset is missing).
class OcrModelException implements Exception {
  const OcrModelException(this.fileName);

  final String fileName;

  @override
  String toString() => 'OcrModelException($fileName)';
}

/// Plain data for the worker isolate: where the files are and what they must
/// hash to.
class OcrModelPaths {
  const OcrModelPaths({
    required this.packId,
    required this.detPath,
    required this.recPath,
    required this.dictPath,
    required this.det,
    required this.rec,
    required this.dict,
  });

  final String packId;
  final String detPath, recPath, dictPath;
  final OcrModelFile det, rec, dict;

  Map<String, Object?> toMap() => {
    'packId': packId,
    'detPath': detPath,
    'recPath': recPath,
    'dictPath': dictPath,
    'det': _fileToMap(det),
    'rec': _fileToMap(rec),
    'dict': _fileToMap(dict),
  };

  factory OcrModelPaths.fromMap(Map<Object?, Object?> m) => OcrModelPaths(
    packId: m['packId']! as String,
    detPath: m['detPath']! as String,
    recPath: m['recPath']! as String,
    dictPath: m['dictPath']! as String,
    det: _fileFromMap(m['det']! as Map),
    rec: _fileFromMap(m['rec']! as Map),
    dict: _fileFromMap(m['dict']! as Map),
  );

  static Map<String, Object?> _fileToMap(OcrModelFile f) => {
    'name': f.name,
    'sha256': f.sha256,
    'bytes': f.bytes,
  };

  static OcrModelFile _fileFromMap(Map<Object?, Object?> m) => OcrModelFile(
    name: m['name']! as String,
    sha256: m['sha256']! as String,
    bytes: m['bytes']! as int,
  );
}

/// Puts the bundled model assets on disk (the engine loads from files; a
/// background isolate has no `rootBundle`). A file is extracted once and again
/// only when it is missing or has the wrong size; the content is verified by
/// the engine (SHA-256) every time it is loaded.
class OcrModelStore {
  OcrModelStore({
    required this.directory,
    required this.loadAsset,
    required this.registry,
    this.assetFolder = 'assets/ocr/models/',
  });

  final Directory directory;
  final Future<ByteData> Function(String assetPath) loadAsset;
  final OcrLanguagePackRegistry registry;
  final String assetFolder;

  /// The calls to [resolve] run one after the other. The camera screen asks
  /// for the models ahead of time (preload) and the first page asks again a
  /// moment later; two extractions of the same file at once wrote the same
  /// `.tmp` file, and the loser failed on the rename (found by the Phase 3
  /// integration test: the first page of a fresh install had no text).
  Future<void> _tail = Future<void>.value();

  /// Throws [OcrModelException] when an asset is missing.
  Future<OcrModelPaths> resolve(OcrLanguagePack pack) {
    final run = _tail.then((_) => _resolve(pack));
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<OcrModelPaths> _resolve(OcrLanguagePack pack) async {
    await directory.create(recursive: true);
    final det = await _ensure(registry.detector);
    final rec = await _ensure(pack.model);
    final dict = await _ensure(pack.dictionary);
    return OcrModelPaths(
      packId: pack.id,
      detPath: det,
      recPath: rec,
      dictPath: dict,
      det: registry.detector,
      rec: pack.model,
      dict: pack.dictionary,
    );
  }

  /// Deletes an extracted file (after it failed verification), so the next
  /// [resolve] extracts it again.
  Future<void> forget(OcrModelFile file) async {
    final target = File(_pathOf(file));
    if (await target.exists()) await target.delete();
  }

  String _pathOf(OcrModelFile file) =>
      '${directory.path}${Platform.pathSeparator}${file.name}';

  Future<String> _ensure(OcrModelFile file) async {
    final target = File(_pathOf(file));
    if (await target.exists() && await target.length() == file.bytes) {
      return target.path;
    }
    final ByteData data;
    try {
      data = await loadAsset('$assetFolder${file.name}');
    } catch (_) {
      throw OcrModelException(file.name);
    }
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    await tmp.rename(target.path);
    return target.path;
  }
}
