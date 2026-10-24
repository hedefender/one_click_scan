import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import '../../domain/ocr/ocr_config.dart';
import 'model_verification.dart';
import 'ocr_model_store.dart';
import 'paddle/ctc_decoder.dart';
import 'paddle/detection_postprocess.dart';
import 'paddle/detection_preprocess.dart';
import 'paddle/paddle_constants.dart';
import 'paddle/pixels.dart';
import 'paddle/text_box.dart';
import 'paddle/recognition_preprocess.dart';

/// Messages between the engine (root isolate) and the worker.
///
/// To the worker: `[id, op, data]` with `op` one of `load`, `recognize`,
/// `release`, `shutdown`, and `[id, 'cancel', targetId]` (handled at once,
/// even while another op runs). From the worker: `[id, 'progress', stage,
/// done, total]` and `[id, 'done', result]`.
///
/// The ops run one after the other (a queue), so a cancelled page is finished
/// before the next starts and two pages never share the memory at once.
abstract final class WorkerOps {
  static const load = 'load';
  static const recognize = 'recognize';
  static const release = 'release';
  static const shutdown = 'shutdown';
  static const cancel = 'cancel';
  static const progress = 'progress';
  static const done = 'done';
}

/// Failure names of the worker, mapped to `OcrFailureReason` by the engine.
abstract final class WorkerFailure {
  static const modelUnavailable = 'modelUnavailable';
  static const imageUnreadable = 'imageUnreadable';
  static const engineError = 'engineError';
}

/// Entry point of the long-lived worker isolate. [args] is
/// `[replyPort, RootIsolateToken?]`.
Future<void> ocrWorkerMain(List<Object?> args) async {
  final reply = args[0]! as SendPort;
  final token = args[1] as RootIsolateToken?;
  if (token != null) BackgroundIsolateBinaryMessenger.ensureInitialized(token);

  final worker = PaddleWorker();
  final port = ReceivePort();
  reply.send(port.sendPort);

  var tail = Future<void>.value();
  port.listen((Object? msg) {
    final m = msg as List;
    final id = m[0] as int;
    final op = m[1] as String;
    if (op == WorkerOps.cancel) {
      worker.cancelled.add(m[2] as int);
      return;
    }
    tail = tail.then((_) async {
      Object? result;
      try {
        result = switch (op) {
          WorkerOps.load => await worker.load(
            OcrModelPaths.fromMap(m[2] as Map),
            (stage, done, total) =>
                reply.send([id, WorkerOps.progress, stage, done, total]),
          ),
          WorkerOps.recognize => await worker.recognize(
            id,
            m[2] as Map,
            (stage, done, total) =>
                reply.send([id, WorkerOps.progress, stage, done, total]),
          ),
          WorkerOps.release => await worker.release().then((_) => null),
          _ => null,
        };
      } catch (error) {
        // Only the type: an error message could carry user content.
        // ignore: avoid_print
        print('ocr worker: ${error.runtimeType} in $op');
        result = _failed(WorkerFailure.engineError);
      }
      reply.send([id, WorkerOps.done, result]);
      if (op == WorkerOps.shutdown) port.close();
    });
  });
}

Map<String, Object?> _failed(String reason) => {
  'status': 'failed',
  'reason': reason,
};

typedef WorkerProgress = void Function(String stage, int done, int total);

/// The Paddle pipeline inside the worker isolate. Sessions stay loaded
/// between pages; everything else is allocated per page and left to the
/// garbage collector (and the tensors disposed) when the page is done.
class PaddleWorker {
  static final _ort = OnnxRuntime();

  /// Ids of ops the engine asked to cancel.
  final cancelled = <int>{};

  OrtSession? _det;
  OrtSession? _rec;
  String? _detPath;
  String? _recPath;
  List<String> _dict = const [];

  bool _isLoaded(OcrModelPaths m) =>
      _det != null &&
      _rec != null &&
      _detPath == m.detPath &&
      _recPath == m.recPath;

  /// Verifies and loads the sessions. Returns a map with `status`.
  Future<Map<String, Object?>> load(
    OcrModelPaths models,
    WorkerProgress progress,
  ) async {
    if (_isLoaded(models)) return {'status': 'ok', 'loadUs': 0};
    final sw = Stopwatch()..start();
    progress('loadingModels', 0, 0);

    // Every file is hashed before it reaches ONNX Runtime. A bad file is
    // deleted by the engine side so the next run extracts it again.
    final bad = <String>[];
    for (final (path, file) in [
      (models.detPath, models.det),
      (models.recPath, models.rec),
      (models.dictPath, models.dict),
    ]) {
      final status = await verifyModelFile(path, file);
      if (status != ModelFileStatus.ok) bad.add(file.name);
    }
    if (bad.isNotEmpty) {
      return {..._failed(WorkerFailure.modelUnavailable), 'bad': bad};
    }

    try {
      if (_detPath != models.detPath) {
        await _det?.close();
        _det = await _session(models.detPath);
        _detPath = models.detPath;
      }
      await _rec?.close();
      _rec = null;
      _rec = await _session(models.recPath);
      _recPath = models.recPath;
      _dict = parseDictionary(await File(models.dictPath).readAsString());
    } catch (error) {
      // ignore: avoid_print
      print('ocr worker: ${error.runtimeType} while loading');
      return _failed(WorkerFailure.engineError);
    }
    return {'status': 'ok', 'loadUs': sw.elapsedMicroseconds};
  }

  Future<OrtSession> _session(String path) => _ort.createSession(
    path,
    options: OrtSessionOptions(
      intraOpNumThreads: OcrConfig.threads,
      providers: const [OrtProvider.CPU],
    ),
  );

  Future<void> release() async {
    final det = _det, rec = _rec;
    _det = _rec = null;
    _detPath = _recPath = null;
    await det?.close();
    await rec?.close();
  }

  bool _stop(int id) => cancelled.remove(id);

  /// Reads one image. [m] has `models` (an [OcrModelPaths] map) and `image`
  /// (path of the upright working copy).
  Future<Map<String, Object?>> recognize(
    int id,
    Map<Object?, Object?> m,
    WorkerProgress progress,
  ) async {
    final loaded = await load(
      OcrModelPaths.fromMap(m['models']! as Map),
      progress,
    );
    if (loaded['status'] != 'ok') return loaded;
    if (_stop(id)) return {'status': 'cancelled'};

    final sw = Stopwatch()..start();
    final det = _det!, rec = _rec!;

    // ------------------------------------------------------------- decode
    progress('detecting', 0, 0);
    final Pixels px;
    try {
      px = _decode(await File(m['image']! as String).readAsBytes());
    } catch (_) {
      return _failed(WorkerFailure.imageUnreadable);
    }
    if (_stop(id)) return {'status': 'cancelled'};

    // ------------------------------------------------------------- detect
    final (dw, dh) = detDims(px.w, px.h, OcrConfig.detectionSide);
    final input = detectionInput(px, dw, dh);
    final tensor = await OrtValue.fromList(input, [1, 3, dh, dw]);
    final out = await det.run({det.inputNames.first: tensor});
    final map = out[det.outputNames.first]!;
    final flat = await map.asFlattenedList();
    await tensor.dispose();
    await map.dispose();
    final prob = flat is Float32List ? flat : Float32List.fromList(flat.cast());
    final boxes = boxesFromMap(prob, dw, dh, px.w / dw, px.h / dh);
    if (_stop(id)) return {'status': 'cancelled'};

    // ---------------------------------------------------------- recognise
    final results = <(String, double)>[];
    progress('recognizing', 0, boxes.length);
    final batch = math.max(1, OcrConfig.recognitionBatch);
    for (var i = 0; i < boxes.length; i += batch) {
      if (_stop(id)) return {'status': 'cancelled'};
      final ids = [
        for (var j = i; j < math.min(i + batch, boxes.length); j++) j,
      ];
      var maxW = 0;
      for (final b in ids) {
        maxW = math.max(maxW, boxes[b].cropWidth);
      }
      final planeLen = 3 * PaddleConstants.recHeight * maxW;
      final data = Float32List(ids.length * planeLen);
      for (var j = 0; j < ids.length; j++) {
        cropInto(px, boxes[ids[j]], data, j * planeLen, maxW);
      }
      final rt = await OrtValue.fromList(data, [
        ids.length,
        3,
        PaddleConstants.recHeight,
        maxW,
      ]);
      final ro = await rec.run({rec.inputNames.first: rt});
      final result = ro[rec.outputNames.first]!;
      final steps = result.shape[1]; // [B, T, C]
      final classes = result.shape[2];
      final rflat = await result.asFlattenedList();
      await result.dispose();
      await rt.dispose();
      final typed = rflat is Float32List
          ? rflat
          : Float32List.fromList(rflat.cast());
      for (var j = 0; j < ids.length; j++) {
        final box = boxes[ids[j]];
        final valid = math.max(
          1,
          math.min(steps, (box.cropWidth * steps / maxW).ceil()),
        );
        results.add(ctcGreedy(typed, j, steps, classes, valid, _dict));
      }
      progress('recognizing', math.min(i + batch, boxes.length), boxes.length);
    }

    // ------------------------------------------------------------- result
    final lines = <Object?>[];
    for (var i = 0; i < boxes.length; i++) {
      final (text, conf) = results[i];
      if (text.trim().isEmpty) continue;
      lines
        ..add(text)
        ..add(conf)
        ..add(boxes[i].row);
      for (final p in boxes[i].quad(px.w, px.h)) {
        lines
          ..add(p.x)
          ..add(p.y);
      }
    }
    return {
      'status': 'ok',
      'lines': lines,
      'width': px.w,
      'height': px.h,
      'boxes': boxes.length,
      'recUs': sw.elapsedMicroseconds,
    };
  }

  /// JPEG (or PNG) bytes to RGB pixels.
  Pixels _decode(Uint8List bytes) {
    var image = img.decodeImage(bytes);
    if (image == null) throw const FormatException('decode');
    if (image.numChannels != 3) image = image.convert(numChannels: 3);
    return Pixels(
      image.getBytes(order: img.ChannelOrder.rgb),
      image.width,
      image.height,
      3,
    );
  }
}

/// Number of values per line in the flat `lines` list of a worker result:
/// text, confidence, row, then eight corner coordinates.
const workerLineStride = 11;
