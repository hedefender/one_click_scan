import 'dart:io';

import 'scan_temp_store.dart';

/// Temporary captured pages live in one directory of the app cache.
class IoScanTempStore implements ScanTempStore {
  const IoScanTempStore(this.directory, {this.alsoPurge = const []});

  final Directory directory;

  /// Other cache directories that [purgeAll] also empties (the Gallery work
  /// folder).
  final List<Directory> alsoPurge;

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
    for (final target in [directory, ...alsoPurge]) {
      try {
        if (await target.exists()) {
          await target.delete(recursive: true);
        }
      } on FileSystemException {
        // Best effort.
      }
    }
  }
}
