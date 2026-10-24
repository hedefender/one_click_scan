import 'dart:io';

import '../../domain/ports/ocr_work_store.dart';

/// Working copies live in one folder of the app cache, so they can all be
/// purged at start-up (a killed run leaves files behind).
class IoOcrWorkStore implements OcrWorkStore {
  IoOcrWorkStore(this.directory);

  final Directory directory;
  var _counter = 0;

  @override
  Future<String> newImagePath() async {
    await directory.create(recursive: true);
    _counter++;
    return '${directory.path}${Platform.pathSeparator}'
        'upright_${DateTime.now().microsecondsSinceEpoch}_$_counter.jpg';
  }

  @override
  Future<void> delete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Best effort: purgeAll removes what stays.
    }
  }

  @override
  Future<void> purgeAll() async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // Best effort.
    }
  }
}
