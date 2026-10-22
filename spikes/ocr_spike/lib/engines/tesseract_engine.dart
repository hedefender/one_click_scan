import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'ocr_engine.dart';

/// Tesseract 5 through a small native channel on tesseract4android 4.9.0
/// (see MainActivity.kt). [variant] is `fast` or `best`: the traineddata of
/// that variant is copied once from the bundled assets to the app's private
/// folder `tess_<variant>/tessdata/`.
class TesseractEngine implements SpikeOcrEngine {
  TesseractEngine(this.variant, {this.language = 'ell+eng', this.psm = 3});

  static const _channel = MethodChannel('spike/tesseract');

  final String variant;
  final String language;
  final int psm;
  int lastInitMs = 0;

  @override
  String get id => 'tesseract_$variant';

  @override
  String get languages => language;

  Future<String> _dataDir() async {
    final base = await getApplicationSupportDirectory();
    final root = Directory('${base.path}/tess_$variant');
    final tessdata = Directory('${root.path}/tessdata');
    await tessdata.create(recursive: true);
    for (final lang in language.split('+')) {
      final file = File('${tessdata.path}/$lang.traineddata');
      if (!file.existsSync()) {
        final data = await rootBundle.load(
          'assets/tessdata_$variant/$lang.traineddata',
        );
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
    }
    return root.path;
  }

  @override
  Future<void> prepare() async {
    await _dataDir();
  }

  @override
  Future<OcrResult> recognize(String imagePath) async {
    final dataDir = await _dataDir();
    final watch = Stopwatch()..start();
    try {
      final reply = await _channel.invokeMapMethod<String, dynamic>(
        'recognize',
        {
          'imagePath': imagePath,
          'dataDir': dataDir,
          'language': language,
          'key': '$variant:$language',
          'psm': psm,
        },
      );
      watch.stop();
      lastInitMs = reply!['initMs'] as int;
      final result = _parse(reply['hocr'] as String, watch.elapsedMilliseconds);
      return OcrResult(
        text: result.text,
        elapsedMs: watch.elapsedMilliseconds,
        lines: result.lines,
        confidence: (reply['confidence'] as int) / 100,
        breakdown: {'init': lastInitMs},
      );
    } catch (e) {
      return OcrResult(
        text: '',
        elapsedMs: watch.elapsedMilliseconds,
        error: e is PlatformException
            ? 'PlatformException ${e.message}'
            : e.runtimeType.toString(),
      );
    }
  }

  OcrResult _parse(String hocr, int ms) {
    final lines = <OcrLine>[];
    final lineRe = RegExp(
      r"""<span class=.ocr_(?:line|header|caption|textfloat).[^>]*title=.[^>]*?bbox (\d+) (\d+) (\d+) (\d+)[^>]*>(.*?)</span>\s*(?=<span class=.ocr_(?:line|header|caption|textfloat).|</p>|</div>)""",
      dotAll: true,
    );
    final wordRe = RegExp(
      r"""<span class=.ocrx_word.[^>]*x_wconf (\d+)[^>]*>(.*?)</span>""",
      dotAll: true,
    );
    final tag = RegExp(r'<[^>]+>');
    for (final m in lineRe.allMatches(hocr)) {
      final words = <String>[];
      var conf = 0.0;
      for (final w in wordRe.allMatches(m.group(5)!)) {
        words.add(_unescape(w.group(2)!.replaceAll(tag, '')));
        conf += int.parse(w.group(1)!) / 100;
      }
      if (words.isEmpty) continue;
      lines.add(
        OcrLine(
          words.join(' '),
          Rect.fromLTRB(
            double.parse(m.group(1)!),
            double.parse(m.group(2)!),
            double.parse(m.group(3)!),
            double.parse(m.group(4)!),
          ),
          confidence: conf / words.length,
        ),
      );
    }
    return OcrResult(
      text: lines.map((l) => l.text).join('\n'),
      elapsedMs: ms,
      lines: lines,
    );
  }

  String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  @override
  Future<void> dispose() async {}
}
