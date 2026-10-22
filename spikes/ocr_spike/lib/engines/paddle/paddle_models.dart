import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'paddle_config.dart';

/// Resolves the bundled models to plain files in the root isolate. The plugin
/// does the same extraction in `createSessionFromAsset` (temp directory, asset
/// file name, extracted once), so a file written by either is reused by the
/// other. Doing it here lets a background isolate load sessions by path
/// without touching `rootBundle`.
class PaddleModels {
  static Future<PaddleModelFiles> resolve(
    String recKey, {
    bool argmax = false,
  }) async {
    final dir = (await getTemporaryDirectory()).path;
    final det = await _extract('assets/models/det_mobile.onnx', dir);
    final rec = await _extract(
      'assets/models/rec_$recKey${argmax ? '_am' : ''}.onnx',
      dir,
    );
    final dict = await rootBundle.loadString('assets/models/dict_$recKey.txt');
    return PaddleModelFiles(detPath: det, recPath: rec, dictText: dict);
  }

  static Future<String> _extract(String asset, String dir) async {
    final file = File('$dir${Platform.pathSeparator}${asset.split('/').last}');
    if (!await file.exists()) {
      final data = await rootBundle.load(asset);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await tmp.rename(file.path);
    }
    return file.path;
  }

  /// Greedy CTC table: index 0 is the blank, then the dictionary, then space.
  static List<String> parseDict(String text) {
    final chars = text.split('\n').map((l) => l.replaceAll('\r', '')).toList();
    if (chars.isNotEmpty && chars.last.isEmpty) chars.removeLast();
    return ['', ...chars, ' '];
  }
}
