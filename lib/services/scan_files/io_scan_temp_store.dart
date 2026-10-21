import 'dart:io';

import 'scan_temp_store.dart';

/// Temporary captured pages live in one directory of the app cache.
class IoScanTempStore implements ScanTempStore {
  const IoScanTempStore(this.directory);

  final Directory directory;

  @override
  Future<void> delete(Iterable<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // Best effort: whatever stays is removed by purgeAll on next start.
      }
    }
  }

  @override
  Future<void> purgeAll() async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException {
      // Best effort.
    }
  }
}
