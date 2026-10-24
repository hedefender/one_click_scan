// Downloads and verifies the bundled OCR models listed in
// assets/ocr/manifest.json.
//
//   dart run tool/ocr_models.dart fetch    download missing/wrong files, verify
//   dart run tool/ocr_models.dart verify   only verify (exit code 1 on problems)
//
// Build-time tool only: the app itself never uses the network.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class ManifestFile {
  ManifestFile(this.name, this.bytes, this.sha256, this.url);
  final String name;
  final int bytes;
  final String sha256;
  final String url;
}

/// Reads the manifest. [root] is the project root.
List<ManifestFile> readManifest(String root) {
  final text = File('$root/assets/ocr/manifest.json').readAsStringSync();
  final json = jsonDecode(text) as Map<String, dynamic>;
  return [
    for (final f in json['files'] as List)
      ManifestFile(
        f['name'] as String,
        f['bytes'] as int,
        f['sha256'] as String,
        f['url'] as String,
      ),
  ];
}

enum FileStatus { ok, missing, wrongSize, wrongHash }

FileStatus checkFile(String root, ManifestFile f) {
  final file = File('$root/assets/ocr/models/${f.name}');
  if (!file.existsSync()) return FileStatus.missing;
  if (file.lengthSync() != f.bytes) return FileStatus.wrongSize;
  final digest = sha256.convert(file.readAsBytesSync()).toString();
  return digest == f.sha256 ? FileStatus.ok : FileStatus.wrongHash;
}

/// Human readable problems; empty when every file is present and correct.
List<String> verifyAll(String root) {
  final problems = <String>[];
  for (final f in readManifest(root)) {
    final status = checkFile(root, f);
    if (status != FileStatus.ok) {
      problems.add('assets/ocr/models/${f.name}: ${status.name}');
    }
  }
  return problems;
}

Future<void> fetchAll(String root) async {
  Directory('$root/assets/ocr/models').createSync(recursive: true);
  final client = HttpClient();
  try {
    for (final f in readManifest(root)) {
      if (checkFile(root, f) == FileStatus.ok) {
        stdout.writeln('ok       ${f.name}');
        continue;
      }
      stdout.writeln('download ${f.name}');
      final request = await client.getUrl(Uri.parse(f.url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException(
          'HTTP ${response.statusCode}',
          uri: Uri.parse(f.url),
        );
      }
      final target = File('$root/assets/ocr/models/${f.name}');
      final sink = target.openWrite();
      await response.pipe(sink);
    }
  } finally {
    client.close();
  }
}

Future<void> main(List<String> args) async {
  final root = Directory.current.path;
  final command = args.isEmpty ? 'verify' : args.first;
  if (command == 'fetch') await fetchAll(root);
  final problems = verifyAll(root);
  if (problems.isEmpty) {
    stdout.writeln('OCR models: all files present, SHA-256 verified.');
    return;
  }
  stderr.writeln('OCR models are not ready:');
  for (final p in problems) {
    stderr.writeln('  $p');
  }
  stderr.writeln('Run tool/fetch_ocr_models.sh to download and verify them.');
  exitCode = 1;
}
