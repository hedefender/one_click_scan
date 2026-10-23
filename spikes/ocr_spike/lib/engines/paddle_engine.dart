import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import 'ocr_engine.dart';
import 'paddle/native_decode.dart';
import 'paddle/paddle_config.dart';
import 'paddle/paddle_models.dart';
import 'paddle/paddle_pixels.dart';

/// PP-OCRv5 (ONNX Runtime through `flutter_onnxruntime`). Everything around
/// the two networks is hand-written (see `paddle/paddle_pixels.dart`): this
/// is the "custom code" whose cost the spike has to measure.
///
/// `const PaddleConfig()` is the Phase 1.5 pipeline. Phase 1.6 adds a timing
/// breakdown (`us_*` keys of [OcrResult.breakdown], microseconds) and the
/// switches of [PaddleConfig].
class PaddleEngine implements SpikeOcrEngine {
  PaddleEngine(
    this.recKey, {
    this.config = const PaddleConfig(),
    this.applyExif = false,
    this.files,
  });

  /// `greek`, `latin` or `eslav` (asset names `rec_<key>.onnx`).
  final String recKey;

  /// Not final only so that the paired A/B study can switch [PaddleConfig.recBatch]
  /// between two runs without reloading the sessions.
  PaddleConfig config;

  /// Bake the EXIF orientation into the pixels before detection. The default
  /// mimics a plain decoder, which ignores the tag.
  final bool applyExif;

  /// Pre-resolved model files (a background isolate has no `rootBundle`).
  PaddleModelFiles? files;

  static final _ort = OnnxRuntime();
  static final _sessions = <String, OrtSession>{};
  static final _dicts = <String, List<String>>{};

  /// Microseconds spent loading by the last [prepare] that loaded something
  /// (`extract`, `loadDet`, `loadRec`); empty when everything was cached.
  Map<String, int> lastLoadUs = const {};

  @override
  String get id => 'paddle_$recKey';

  @override
  String get languages => recKey;

  /// Closes every loaded session, so the next [prepare] loads again (cold).
  static Future<void> releaseAll() async {
    final all = _sessions.values.toList();
    _sessions.clear();
    for (final s in all) {
      await s.close();
    }
  }

  Future<OrtSession> _session(String path) async {
    final key = '$path|${config.sessionKey}';
    final cached = _sessions[key];
    if (cached != null) return cached;
    final session = await _ort.createSession(
      path,
      options: OrtSessionOptions(
        intraOpNumThreads: config.threads,
        providers: config.providers,
        sessionConfigs: config.allowSpinning == null
            ? null
            : {
                'session.intra_op.allow_spinning': config.allowSpinning!
                    ? '1'
                    : '0',
              },
      ),
    );
    return _sessions[key] = session;
  }

  @override
  Future<void> prepare() async {
    final t = StageTimer();
    files ??= await PaddleModels.resolve(recKey, argmax: config.recArgmax);
    t.lap('extract');
    final f = files!;
    final hadDet = _sessions.containsKey('${f.detPath}|${config.sessionKey}');
    final hadRec = _sessions.containsKey('${f.recPath}|${config.sessionKey}');
    await _session(f.detPath);
    t.lap('loadDet');
    await _session(f.recPath);
    t.lap('loadRec');
    _dicts.putIfAbsent(f.recPath, () => PaddleModels.parseDict(f.dictText));
    if (!hadDet || !hadRec) lastLoadUs = t.micros;
  }

  @override
  Future<OcrResult> recognize(String imagePath) async {
    try {
      await prepare();
      final t = StageTimer();
      final Pixels px;
      if (config.decode == DecodeMode.native) {
        px = await decodeNative(imagePath, config.maxSide, t);
      } else {
        final bytes = await File(imagePath).readAsBytes();
        t.lap('read');
        var image = img.decodeImage(bytes);
        if (image == null) throw StateError('decode');
        t.lap('decode');
        if (applyExif) image = img.bakeOrientation(image);
        if (image.numChannels == 4) image = image.convert(numChannels: 3);
        px = Pixels(
          image.getBytes(order: img.ChannelOrder.rgb),
          image.width,
          image.height,
          3,
        );
        t.lap('toRgb');
      }
      return await recognizePixels(px, t);
    } catch (e, st) {
      // ignore: avoid_print
      print('paddle error ${_errorName(e)}: $e\n$st');
      return OcrResult(text: '', elapsedMs: 0, error: _errorName(e));
    }
  }

  static String _errorName(Object e) => e is PlatformException
      ? 'PlatformException:${e.code}'
      : '${e.runtimeType}';

  /// The pipeline from decoded pixels. [t] has already been charged for the
  /// decoding stages.
  Future<OcrResult> recognizePixels(Pixels px, StageTimer t) async {
    try {
      final f = files!;
      final det = await _session(f.detPath);
      final rec = await _session(f.recPath);
      final dict = _dicts[f.recPath]!;
      t.skip();

      // ------------------------------------------------------------- detect
      final (dw, dh) = detDims(px.w, px.h, config.detSide);
      final input = config.fastPixels
          ? detInputFast(px, dw, dh)
          : detInputLegacy(px, dw, dh);
      t.lap('detPre');
      final tensor = await OrtValue.fromList(input, [1, 3, dh, dw]);
      t.lap('detIn');
      final out = await det.run({det.inputNames.first: tensor});
      t.lap('detInfer');
      final map = out[det.outputNames.first]!;
      final flat = await map.asFlattenedList();
      await tensor.dispose();
      await map.dispose();
      t.lap('detOut');
      final Float32List prob;
      if (config.fastPixels) {
        prob = flat is Float32List ? flat : Float32List.fromList(flat.cast());
      } else {
        prob = Float32List(dh * dw);
        for (var i = 0; i < prob.length; i++) {
          prob[i] = (flat[i] as num).toDouble();
        }
      }
      t.lap('detConv');
      final boxes = config.fastPixels
          ? boxesFromMapFast(prob, dw, dh, px.w / dw, px.h / dh)
          : boxesFromMapLegacy(prob, dw, dh, px.w / dw, px.h / dh);
      t.lap('detPost');

      // ---------------------------------------------------------- recognise
      final results = List<(String, double)?>.filled(boxes.length, null);
      final order = List<int>.generate(boxes.length, (i) => i);
      final batch = math.max(1, config.recBatch);
      if (batch > 1) {
        order.sort((a, b) => boxes[a].cropWidth.compareTo(boxes[b].cropWidth));
      }
      var calls = 0, inferMaxUs = 0;
      for (var i = 0; i < order.length; i += batch) {
        final ids = order.sublist(i, math.min(i + batch, order.length));
        var maxW = 0;
        for (final id in ids) {
          maxW = math.max(maxW, boxes[id].cropWidth);
        }
        final planeLen = 3 * recHeight * maxW;
        final data = Float32List(ids.length * planeLen);
        for (var j = 0; j < ids.length; j++) {
          final box = boxes[ids[j]];
          if (config.fastPixels) {
            cropInto(px, box, data, j * planeLen, maxW);
          } else {
            copyCropInto(
              cropLegacy(px, box),
              box.cropWidth,
              data,
              j * planeLen,
              maxW,
            );
          }
        }
        t.lap('recCrop');
        final rt = await OrtValue.fromList(data, [
          ids.length,
          3,
          recHeight,
          maxW,
        ]);
        t.lap('recIn');
        final inferStart = t.totalUs;
        final ro = await rec.run({rec.inputNames.first: rt});
        t.lap('recInfer');
        inferMaxUs = math.max(inferMaxUs, t.totalUs - inferStart);
        calls++;
        List<dynamic> rflat = const [];
        List<dynamic> pflat = const [];
        int steps, classes = 0;
        if (config.recArgmax) {
          final idx = ro['idx']!, prob = ro['prob']!;
          steps = idx.shape[1]; // [B, T]
          rflat = await idx.asFlattenedList();
          pflat = await prob.asFlattenedList();
          await idx.dispose();
          await prob.dispose();
        } else {
          final result = ro[rec.outputNames.first]!;
          steps = result.shape[1]; // [B, T, C]
          classes = result.shape[2];
          rflat = await result.asFlattenedList();
          await result.dispose();
        }
        await rt.dispose();
        t.lap('recOut');
        final Float32List? typed = config.fastPixels && !config.recArgmax
            ? (rflat is Float32List
                  ? rflat
                  : Float32List.fromList(rflat.cast()))
            : null;
        for (var j = 0; j < ids.length; j++) {
          final box = boxes[ids[j]];
          final valid = math.max(
            1,
            math.min(steps, (box.cropWidth * steps / maxW).ceil()),
          );
          results[ids[j]] = config.recArgmax
              ? ctcArgmax(rflat, pflat, j, steps, valid, dict)
              : typed != null
              ? ctcFast(typed, j, steps, classes, valid, dict)
              : ctcLegacy(rflat, j, steps, classes, valid, dict);
        }
        t.lap('recCtc');
      }

      final items = <_Item>[];
      for (var i = 0; i < boxes.length; i++) {
        final (text, conf) = results[i]!;
        if (text.trim().isEmpty) continue;
        items.add(_Item(boxes[i], text, conf));
      }
      final lines = _toLines(items);
      t.lap('lines');
      final confs = items.map((i) => i.conf).toList();
      return OcrResult(
        text: lines.map((l) => l.text).join('\n'),
        elapsedMs: (t.totalUs / 1000).round(),
        lines: [
          for (final i in items)
            OcrLine(i.text, i.box.bounds, confidence: i.conf),
        ],
        confidence: confs.isEmpty
            ? null
            : confs.reduce((a, b) => a + b) / confs.length,
        breakdown: {
          for (final e in t.micros.entries) 'us_${e.key}': e.value,
          'us_total': t.totalUs,
          'us_recInferMax': inferMaxUs,
          'boxes': boxes.length,
          'recCalls': calls,
          'imgW': px.w,
          'imgH': px.h,
          'detW': dw,
          'detH': dh,
        },
      );
    } catch (e, st) {
      // ignore: avoid_print
      print('paddle error ${_errorName(e)}: $e\n$st');
      return OcrResult(
        text: '',
        elapsedMs: (t.totalUs / 1000).round(),
        error: _errorName(e),
      );
    }
  }

  List<_TextLine> _toLines(List<_Item> items) {
    final lines = <_TextLine>[];
    List<_Item>? row;
    for (final item in items) {
      if (row != null && item.box.row == row.first.box.row) {
        row.add(item);
      } else {
        row = [item];
        lines.add(_TextLine(row));
      }
    }
    return lines;
  }

  @override
  Future<void> dispose() async {}
}

class _Item {
  _Item(this.box, this.text, this.conf);
  final PBox box;
  final String text;
  final double conf;
}

class _TextLine {
  _TextLine(this.items);
  final List<_Item> items;
  String get text => items.map((i) => i.text).join(' ');
}
