import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../domain/ocr/ocr_language_pack.dart';

enum ModelFileStatus { ok, missing, wrongSize, wrongHash }

/// Checks a model file against what the pack list says: it exists, has the
/// expected size and the expected SHA-256 (streamed, the file is never loaded
/// whole into memory). Used every time a model is loaded from a file, so a
/// damaged or swapped file never reaches the engine.
Future<ModelFileStatus> verifyModelFile(
  String path,
  OcrModelFile expected,
) async {
  final file = File(path);
  if (!await file.exists()) return ModelFileStatus.missing;
  if (await file.length() != expected.bytes) return ModelFileStatus.wrongSize;
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString() == expected.sha256
      ? ModelFileStatus.ok
      : ModelFileStatus.wrongHash;
}
